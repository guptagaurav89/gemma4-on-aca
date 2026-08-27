# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: Copyright contributors to the vLLM project
"""Example Python client for OpenAI Chat Completion using vLLM API server
NOTE: start a supported chat completion model server with `vllm serve`, e.g.
    vllm serve meta-llama/Llama-2-7b-chat-hf
"""

import argparse
import base64
import mimetypes
from urllib.parse import urlparse
import dotenv
import os

dotenv.load_dotenv()

from openai import OpenAI

# Modify OpenAI's API key and API base to use vLLM's API server.
openai_api_key = os.environ.get("OPENAI_API_KEY", "EMPTY")
openai_api_base = os.environ.get(
    "OPENAI_API_BASE",
    "EMPTY",
)

if openai_api_base == "EMPTY":
    print("Warning: OPENAI_API_BASE is not set.")

DEFAULT_TEXT_PROMPT = "Who won the cricket world cup in 2024? Where was it played?"
DEFAULT_IMAGE_PROMPT = "Describe what you see in this image in detail."


def parse_args():
    parser = argparse.ArgumentParser(description="Client for vLLM API server")
    parser.add_argument(
        "--stream", action="store_true", help="Enable streaming response"
    )
    parser.add_argument(
        "--image",
        help="Path to a local image file or an image URL to analyze",
    )
    parser.add_argument(
        "--prompt",
        help="Question/instruction to send along with the (optional) image",
    )
    return parser.parse_args()


def encode_image_as_data_url(image_path: str) -> str:
    """Read a local image file and return it as a base64 data URL."""
    mime_type, _ = mimetypes.guess_type(image_path)
    if mime_type is None:
        mime_type = "image/jpeg"
    with open(image_path, "rb") as image_file:
        encoded = base64.b64encode(image_file.read()).decode("utf-8")
    return f"data:{mime_type};base64,{encoded}"


def resolve_image_url(image: str) -> str:
    """Return a usable image URL, base64-encoding local file paths."""
    if urlparse(image).scheme in ("http", "https"):
        return image
    return encode_image_as_data_url(image)


def build_messages(args) -> list:
    if args.image:
        prompt = args.prompt or DEFAULT_IMAGE_PROMPT
        image_url = resolve_image_url(args.image)
        user_content = [
            {"type": "text", "text": prompt},
            {"type": "image_url", "image_url": {"url": image_url}},
        ]
    else:
        user_content = args.prompt or DEFAULT_TEXT_PROMPT

    return [
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": user_content},
    ]


def main(args):
    client = OpenAI(
        # defaults to os.environ.get("OPENAI_API_KEY")
        api_key=openai_api_key,
        base_url=openai_api_base,
    )

    models = client.models.list()

    print("Models on vLLM- ")
    print(models)
    model = models.data[0].id

    messages = build_messages(args)

    # Chat Completion API
    chat_completion = client.chat.completions.create(
        messages=messages,
        model=model,
        stream=args.stream,
    )

    print("-" * 50)
    print("Chat completion results:")
    if args.stream:
        for c in chat_completion:
            print(c)
    else:
        print(chat_completion)
    print("-" * 50)


if __name__ == "__main__":
    args = parse_args()
    main(args)
