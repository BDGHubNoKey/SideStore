FROM python:3.9-slim

WORKDIR /app

# Install dependencies
RUN apt-get update && apt-get install -y \
    libssl-dev \
    libffi-dev \
    python3-dev \
    git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy requirements and install dependencies
COPY flask_backend/requirements.txt .

# Install pymobiledevice3 version 2.30.0 and construct 2.10.69 to ensure JIT functionality works
# This fixes the "No such command 'start-quic-tunnel'" error in newer versions
RUN pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir pymobiledevice3==2.30.0 construct==2.10.69

# Copy application code
COPY flask_backend/ .

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV FLASK_APP=production_app.py
ENV PORT=5000

# Expose port
EXPOSE 5000

# Run the application with Gunicorn
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "4", "production_app:app"]
