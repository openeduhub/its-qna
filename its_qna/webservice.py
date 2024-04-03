import argparse

import torch
import uvicorn
from fastapi import FastAPI
from llama_index.core.prompts import PromptTemplate
from llama_index.llms.huggingface import HuggingFaceLLM
from pydantic import BaseModel
from transformers import BitsAndBytesConfig
from transformers.utils.import_utils import is_bitsandbytes_available

from its_qna._version import __version__


def get_llm(model_name: str) -> HuggingFaceLLM:
    quantization_config = (
        BitsAndBytesConfig(
            load_in_4bit=True,
            bnb_4bit_compute_dtype=torch.float16,
            bnb_4bit_quant_type="nf4",
            bnb_4bit_use_double_quant=True,
        )
        if is_bitsandbytes_available()
        else None
    )

    query_wrapper_prompt = PromptTemplate("<|user|>\n{query_str}\n" "<|assistant|>")

    llm = HuggingFaceLLM(
        model_name=model_name,
        tokenizer_name=model_name,
        context_window=2**11,
        max_new_tokens=2**8,
        system_prompt="<|system|>\nYou are a system for question-and-answer generation in German. Generate question-answer pairs from the given text.",
        model_kwargs={"quantization_config": quantization_config},
        query_wrapper_prompt=query_wrapper_prompt,
        device_map="auto",
    )

    return llm


class QueryInput(BaseModel):
    text: str


class QueryResult(BaseModel):
    text: str


def main():
    # define CLI arguments
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--port", action="store", default=8080, help="Port to listen on", type=int
    )
    parser.add_argument(
        "--host", action="store", default="0.0.0.0", help="Hosts to listen to", type=str
    )
    parser.add_argument(
        "--version",
        action="version",
        version="%(prog)s {version}".format(version=__version__),
    )
    parser.add_argument(
        "--model-name",
        default="TinyLlama/TinyLlama-1.1B-Chat-v1.0",
        help="The name of the Huggingface model to use.",
    )

    # read passed CLI arguments
    args = parser.parse_args()

    llm = get_llm(args.model_name)

    # create and run REST api
    app = FastAPI()

    @app.get("/_ping")
    def _ping():
        pass

    @app.post("/query")
    def query(inp: QueryInput) -> QueryResult:
        return QueryResult(text=llm.complete(inp.text).text)

    uvicorn.run(
        app,
        host=args.host,
        port=args.port,
        reload=False,
    )


if __name__ == "__main__":
    main()
