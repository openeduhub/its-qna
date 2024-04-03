#!/usr/bin/env python3
from setuptools import find_packages, setup

setup(
    name="its-qna",
    version="0.1.0",
    description="A Python application",
    author="",
    author_email="",
    packages=find_packages(),
    install_requires=[
        d for d in open("requirements.txt").readlines() if not d.startswith("--")
    ],
    entry_points={"console_scripts": ["its-qna = its_qna.webservice:main"]},
)
