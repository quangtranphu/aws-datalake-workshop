"""
Steering handlers for the GDELT data analyst agent.
Uses a plain SteeringHandler with a direct boto3 Bedrock call for LLM evaluation,
avoiding the LLMSteering tool-registry error that LLMSteeringHandler causes
under agentcore dev / agentcore deploy on a local machine.
"""

import boto3
from strands.vended_plugins.steering import (
    SteeringHandler,
    LedgerProvider,
    Proceed,
    Guide,
    ToolSteeringAction,
)

_RETRIEVAL_TOOLS = {"retrieve_gdelt_events", "list_gdelt_files"}


class DataGroundingGuardrail(SteeringHandler):
    """LLM-based guardrail ensuring the agent grounds answers in retrieved GDELT data.

    Uses a separate evaluator model (Haiku) via direct boto3 converse() call
    instead of LLMSteeringHandler's internal LLMSteering tool, which fails to
    register in the tool registry under agentcore dev / agentcore deploy.

    A different model family provides independent evaluation free from the
    self-evaluation bias that occurs when the agent model judges its own output.
    """

    name = "data-grounding-guardrail"

    _DEFAULT_MODEL = "anthropic.claude-3-haiku-20240307-v1:0"

    _EVAL_SYSTEM = """You are evaluating a GDELT data analyst agent's responses.
Enforce these guidelines:

- Responses must be grounded in data retrieved from tools (knowledge base results,
  reference lookups). The agent must not invent specific event dates, counts,
  actor names, or Goldstein scores.
- If the agent makes a claim it cannot support from tool output, it must call
  retrieve_gdelt_events or a lookup tool first.
- The agent should cite the source S3 file when quoting specific records.
- Answers must be factual, concise, and clearly scoped to what the data shows.

Reply with exactly one of:
  PASS
  FAIL: <one sentence describing the specific violation>"""

    def __init__(self, model_id: str = _DEFAULT_MODEL):
        super().__init__(context_providers=[LedgerProvider()])
        self._model_id = model_id
        self._client = boto3.client("bedrock-runtime")

    async def steer_after_model(self, *, agent, **kwargs) -> ToolSteeringAction:
        ledger = self.steering_context.data.get("ledger", {})
        tool_calls = ledger.get("tool_calls", [])

        messages = getattr(agent, "messages", []) or []
        last = next(
            (m for m in reversed(messages) if m.get("role") == "assistant"),
            None,
        )
        if not last:
            return Proceed(reason="No assistant message to evaluate")

        content = last.get("content", "")
        text = content if isinstance(content, str) else " ".join(
            b.get("text", "") for b in content if isinstance(b, dict)
        )
        if not text.strip():
            return Proceed(reason="Empty response")

        has_retrieved = any(
            c["tool_name"] in _RETRIEVAL_TOOLS and c["status"] == "success"
            for c in tool_calls
        )

        try:
            response = self._client.converse(
                modelId=self._model_id,
                system=[{"text": self._EVAL_SYSTEM}],
                messages=[{
                    "role": "user",
                    "content": [{
                        "text": (
                            f"Retrieval tools were called: {has_retrieved}\n\n"
                            f"Agent response to evaluate:\n\n{text}"
                        ),
                    }],
                }],
                inferenceConfig={"maxTokens": 200, "temperature": 0},
            )
            verdict = response["output"]["message"]["content"][0]["text"].strip()
        except Exception as exc:
            return Proceed(reason=f"Guardrail evaluator unavailable: {exc}")

        if verdict.upper().startswith("FAIL"):
            return Guide(reason=verdict[5:].strip())

        return Proceed(reason="Data grounding check passed")


data_grounding_guardrail = DataGroundingGuardrail()
