FROM python:3.12-slim

# health_app.py is stdlib-only: no pip install, no gunicorn needed.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    HEALTH_APP_PORT=8080

WORKDIR /app

COPY health_app.py /app/health_app.py

# Match the pod securityContext (uid 10001, no login shell, no home dir).
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin app

USER 10001

EXPOSE 8080

# Kubernetes uses the /health probes; this only helps plain `docker run`.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python3 -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=2).status == 200 else 1)"

CMD ["python3", "/app/health_app.py"]
