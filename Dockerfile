FROM python:3.10-slim

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends build-essential && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY src/ src/
COPY app/ app/

# Model artifacts — must be built before docker build (make export-models)
# Create directory even if empty so the app starts without models
RUN mkdir -p outputs/models
COPY outputs/models/ outputs/models/

EXPOSE 8080

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
