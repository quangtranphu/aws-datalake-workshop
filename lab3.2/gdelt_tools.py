"""
GDELT (Global Database of Events, Language, and Tone) tools.
Knowledge base data source: s3://sdl-immersion-day-220334428465/gdelt/
Reference files (eventcode.txt, countries.txt, types.txt, groups.txt) are
read from the same S3 prefix and cached after the first load.
"""

import os
from functools import lru_cache
import boto3
from botocore.exceptions import ClientError
from strands import tool

GDELT_S3_BUCKET = "sdl-immersion-day-220334428465"
GDELT_S3_PREFIX = "gdelt/"


# ---------------------------------------------------------------------------
# Reference data helpers
# ---------------------------------------------------------------------------

def _read_s3_text(key: str) -> str:
    s3 = boto3.client("s3")
    obj = s3.get_object(Bucket=GDELT_S3_BUCKET, Key=key)
    return obj["Body"].read().decode("utf-8")


@lru_cache(maxsize=4)
def _load_reference(filename: str) -> dict[str, str]:
    """
    Parse a tab-separated reference file from S3 into a {code: label} dict.
    All four reference files share the same two-column TSV format with a header row.
    Results are cached in memory so S3 is only hit once per file per process lifetime.
    """
    text = _read_s3_text(GDELT_S3_PREFIX + filename)
    mapping: dict[str, str] = {}
    for line in text.strip().splitlines()[1:]:   # skip header
        parts = line.strip().split(None, 1)  # handles tab or space-separated files
        if len(parts) == 2:
            mapping[parts[0].strip()] = parts[1].strip()
    return mapping


# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------

@tool
def retrieve_gdelt_events(query: str) -> str:
    """
    Search the GDELT knowledge base for global events matching a natural-language query.
    Requires the KNOWLEDGE_BASE_ID environment variable (output from Terraform).
    Falls back to listing available S3 files when the variable is not set.
    Args:
        query: Natural-language description of events to find, e.g.
               'protests in the Middle East 2015',
               'military conflict between Russia and Ukraine',
               'ceasefire negotiations in Africa'
    """
    kb_id = os.environ.get("KNOWLEDGE_BASE_ID", "")
    if not kb_id:
        return _list_gdelt_s3()

    try:
        client = boto3.client("bedrock-agent-runtime")
        response = client.retrieve(
            knowledgeBaseId=kb_id,
            retrievalQuery={"text": query},
            retrievalConfiguration={
                "vectorSearchConfiguration": {"numberOfResults": 5}
            },
        )
        results = response.get("retrievalResults", [])
        if not results:
            return f"No GDELT events found for: '{query}'"

        lines: list[str] = []
        for i, r in enumerate(results, 1):
            text = r.get("content", {}).get("text", "").strip()
            score = r.get("score", 0.0)
            uri = r.get("location", {}).get("s3Location", {}).get("uri", "")
            lines.append(f"Result {i} (score {score:.3f}):\n{text}\nSource: {uri}")
        return "\n\n---\n\n".join(lines)

    except ClientError as exc:
        return f"Knowledge base retrieval error: {exc.response['Error']['Message']}"


@tool
def list_gdelt_files(sub_prefix: str = "") -> str:
    """
    List files and folders in the GDELT S3 knowledge base.
    Args:
        sub_prefix: Optional path within gdelt/ to narrow the listing,
                    e.g. '2015/' or 'events/'. Leave empty for the top level.
    """
    return _list_gdelt_s3(sub_prefix)


@tool
def lookup_event_code(code: str) -> str:
    """
    Return the plain-English description for a CAMEO event code.
    Supports prefix search: passing '14' returns all codes starting with '14'.
    Args:
        code: CAMEO event code such as '14', '051', or '1821'
    """
    codes = _load_reference("eventcodes/eventcode.txt")
    key = code.strip()
    if key in codes:
        return f"CAMEO {key}: {codes[key]}"

    matches = [(k, v) for k, v in codes.items() if k.startswith(key)]
    if matches:
        lines = [f"{k}: {v}" for k, v in sorted(matches)[:15]]
        return f"Codes starting with '{key}':\n" + "\n".join(lines)
    return f"No CAMEO event code found for '{code}'. Top-level codes run from 01 to 20."


@tool
def lookup_country_code(code: str) -> str:
    """
    Return the country or region name for a GDELT 3-letter geo code.
    Also supports name search: passing 'Syria' returns matching codes.
    Args:
        code: 3-letter code such as 'USA', 'SYR', or region tag 'MEA'
    """
    countries = _load_reference("countries/countries.txt")
    upper = code.strip().upper()
    if upper in countries:
        return f"{upper}: {countries[upper]}"

    query = code.strip().lower()
    matches = [(k, v) for k, v in countries.items() if query in v.lower()]
    if matches:
        lines = [f"{k}: {v}" for k, v in sorted(matches)[:10]]
        return f"Countries/regions matching '{code}':\n" + "\n".join(lines)
    return f"No country/region code found for '{code}'."


@tool
def lookup_actor_type(code: str) -> str:
    """
    Return the description for a GDELT actor type or group code.
    Searches both types.txt (individual actor types) and groups.txt (organisations).
    Args:
        code: Actor type such as 'GOV', 'MIL', 'MED', or group such as 'NATO', 'UNO'
    """
    types = _load_reference("types/types.txt")
    groups = _load_reference("groups/groups.txt")
    upper = code.strip().upper()

    label = types.get(upper) or groups.get(upper)
    if label:
        return f"{upper}: {label}"

    combined = {**types, **groups}
    matches = {k: v for k, v in combined.items() if upper in k or upper in v.upper()}
    if matches:
        lines = [f"{k}: {v}" for k, v in sorted(matches.items())[:10]]
        return f"Actor codes matching '{code}':\n" + "\n".join(lines)
    return f"No actor type or group code found for '{code}'."


# ---------------------------------------------------------------------------
# Internal helper
# ---------------------------------------------------------------------------

def _list_gdelt_s3(sub_prefix: str = "") -> str:
    s3 = boto3.client("s3")
    full_prefix = GDELT_S3_PREFIX + sub_prefix
    try:
        paginator = s3.get_paginator("list_objects_v2")
        entries: list[str] = []
        for page in paginator.paginate(
            Bucket=GDELT_S3_BUCKET,
            Prefix=full_prefix,
            Delimiter="/",
            PaginationConfig={"MaxItems": 50},
        ):
            for cp in page.get("CommonPrefixes", []):
                entries.append(f"[folder] {cp['Prefix']}")
            for obj in page.get("Contents", []):
                size_kb = obj["Size"] // 1024
                entries.append(
                    f"{obj['Key']}  ({size_kb} KB, modified {obj['LastModified'].date()})"
                )
        if not entries:
            return f"No files found under s3://{GDELT_S3_BUCKET}/{full_prefix}"
        header = f"Contents of s3://{GDELT_S3_BUCKET}/{full_prefix} ({len(entries)} items):"
        return header + "\n" + "\n".join(entries[:50])
    except ClientError as exc:
        return f"S3 listing error: {exc.response['Error']['Message']}"
