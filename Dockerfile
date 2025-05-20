FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirments.txt

COPY . .

EXPOSE 5000
CMD ["python", "api.py"]
