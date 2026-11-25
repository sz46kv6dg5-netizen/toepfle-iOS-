module.exports = {
  apps: [
    {
      name: "toepfle-backend",
      cwd: __dirname,
      script: "venv/bin/uvicorn",
      args: "main:app --host 127.0.0.1 --port 8015 --workers 2",
      interpreter: "none",
      autorestart: true,
      watch: false,
      max_memory_restart: "1G",
      env: {
        NODE_ENV: "production",
      },
    },
  ],
};
