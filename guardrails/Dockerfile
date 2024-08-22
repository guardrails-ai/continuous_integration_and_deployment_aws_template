FROM python:3.12-slim

ARG GUARDRAILS_TOKEN
ARG GUARDRAILS_SDK_VERSION="guardrails-ai[api]>=0.5.0,<6"

# Set environment variables to avoid writing .pyc files and to unbuffer Python output
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
# These are purposefully low for initialization and development
# set to WARN or higher in production
ENV LOGLEVEL="DEBUG"
ENV GUARDRAILS_LOG_LEVEL="DEBUG"
ENV APP_ENVIRONMENT="production"

WORKDIR /app

# Install Git and necessary dependencies
RUN apt-get update && \
    apt-get install -y git curl gcc jq && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN pip install --upgrade pip

# Install guardrails, the guardrails API, and gunicorn
RUN pip install $GUARDRAILS_SDK_VERSION "gunicorn"

RUN guardrails configure --enable-metrics --enable-remote-inferencing --token $GUARDRAILS_TOKEN

# bring in base template
COPY guardrails/chatbot.json /app/chatbot.json

# un comment this and comment out the RUN guardrails create if using a customized config.py
# COPY guardrails/config.py

# Install Hub Deps and create config.py
RUN guardrails create --template /app/chatbot.json

# Expose port 8000 for the application
EXPOSE 8000

# Command to start the Gunicorn server with specified settings
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--timeout=5", "--threads=3", "guardrails_api.app:create_app()"]
