# Guardrails continuous integration and deployment quick start - aws

This repository can be used as a template to configure, verify and deploy a guardrails ai backend server.

To build run and test this locally
```
cd guardrails
docker build -t gr-backend-images:latest --no-cache --progress=plain --build-arg GUARDRAILS_TOKEN=[YOUR GUARDRAILS TOKEN] .
docker run -d -p 8000:8000 -e OPENAI_API_KEY=[YOUR OPENAI KEY] gr-backend-images:latest
pip install pytest
pytest tests/
```

You may get a Guardrails token from https://hub.guardrailsai.com/keys

See https://www.guardrailsai.com/docs/how_to_guides/continuous_integration_continuous_deployment for more information