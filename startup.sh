cd /app
gunicorn --bind=0.0.0.0 --workers=10 startup:app
