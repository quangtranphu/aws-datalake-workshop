import json
import logging
import os
from strands import Agent
from bedrock_agentcore.runtime import BedrockAgentCoreApp
from gdelt_tools import (
    retrieve_gdelt_events,
    list_gdelt_files,
    lookup_event_code,
    lookup_country_code,
    lookup_actor_type,
)
from steering_handlers import data_grounding_guardrail

logger = logging.getLogger(__name__)

app = BedrockAgentCoreApp()

SYSTEM_PROMPT = """
You are a GDELT (Global Database of Events, Language, and Tone) data analyst.
GDELT monitors the world's broadcast, print, and web news and codes events using the
CAMEO (Conflict and Mediation Event Observations) framework.

Knowledge base: s3://sdl-immersion-day-220334428465/gdelt/

Your capabilities:
- Search for global events by topic, country, actor, or time period using retrieve_gdelt_events
- Decode CAMEO event codes with lookup_event_code
- Resolve country and region codes with lookup_country_code
- Identify actor types and international groups with lookup_actor_type
- Browse available data files with list_gdelt_files

Guidelines:
- Always retrieve data before making claims about specific events, dates, or statistics.
- When presenting events, include: date, actors (Actor1 / Actor2), event type (decoded CAMEO code),
  Goldstein scale score (conflict/cooperation tone, -10 to +10), and source URL when available.
- Goldstein scale: positive = cooperative, negative = conflictual.
- Offer to decode any codes the user may not recognise.
- Be precise and cite the source file when quoting records from the knowledge base.
"""

_agent = None

def get_agent() -> Agent:
    global _agent
    if _agent is None:
        _agent = Agent(
            tools=[
                retrieve_gdelt_events,
                list_gdelt_files,
                lookup_event_code,
                lookup_country_code,
                lookup_actor_type,
            ],
            plugins=[data_grounding_guardrail],
            system_prompt=SYSTEM_PROMPT,
            context_manager="auto",
        )
    return _agent


@app.entrypoint
def invoke(payload, context):
    raw_prompt = payload.get("prompt")
    try:
        parsed = json.loads(raw_prompt)
        prompt = parsed.get("prompt", raw_prompt)
    except (TypeError, json.JSONDecodeError):
        prompt = raw_prompt

    if not prompt:
        raise ValueError("Missing required field: prompt")

    agent = get_agent()
    response = agent(prompt)
    return str(response).strip()


if __name__ == "__main__":
    app.run()
