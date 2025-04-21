# SideStore JIT Backend Deployment Guide

This guide provides instructions for deploying the SideStore JIT Backend to various environments.

## Prerequisites

- Python 3.8+
- pip
- A server or cloud platform to host the backend
- (Optional) Docker for containerized deployment

## Local Deployment for Testing

1. Clone the repository
2. Install dependencies:
   ```bash
   cd flask_backend
   pip install -r requirements.txt
   ```
3. Run the development server:
   ```bash
   export FLASK_ENV=development
   export FLASK_APP=app.py
   flask run --host=0.0.0.0 --port=5000
   ```

## Docker Deployment

1. Build the Docker image:
   ```bash
   cd flask_backend
   docker build -t sidestore-jit-backend .
   ```

2. Run the container:
   ```bash
   docker run -d -p 5000:5000 -e JWT_SECRET_KEY=your_secret_key sidestore-jit-backend
   ```

## Cloud Deployment Options

### Heroku

1. Create a new Heroku app:
   ```bash
   heroku create sidestore-jit-backend
   ```

2. Set environment variables:
   ```bash
   heroku config:set JWT_SECRET_KEY=your_secret_key
   heroku config:set FLASK_APP=production_app.py
   ```

3. Deploy the app:
   ```bash
   git push heroku main
   ```

### AWS Elastic Beanstalk

1. Initialize Elastic Beanstalk:
   ```bash
   eb init -p python-3.8 sidestore-jit-backend
   ```

2. Create an environment:
   ```bash
   eb create sidestore-jit-backend-env
   ```

3. Set environment variables:
   ```bash
   eb setenv JWT_SECRET_KEY=your_secret_key
   ```

4. Deploy the app:
   ```bash
   eb deploy
   ```

### DigitalOcean App Platform

1. Create a new app on DigitalOcean App Platform
2. Connect your repository
3. Set environment variables:
   - `JWT_SECRET_KEY=your_secret_key`
   - `FLASK_APP=production_app.py`
4. Deploy the app

## Security Considerations

1. **JWT Secret Key**: Always use a strong, unique JWT secret key in production.
2. **HTTPS**: Ensure your deployment uses HTTPS to encrypt communication between SideStore and the backend.
3. **Rate Limiting**: Consider implementing rate limiting to prevent abuse.
4. **Database**: For production, replace the in-memory storage with a proper database like PostgreSQL.
5. **Monitoring**: Set up monitoring and logging to track usage and detect issues.

## Configuring SideStore

After deploying the backend, you need to configure SideStore to use it:

1. Open SideStore on your iOS device
2. Go to Settings > Techy Things > JIT API Settings
3. Enter the URL of your deployed backend (e.g., `https://your-backend-url.com`)
4. Save the settings

## Troubleshooting

### Common Issues

1. **Connection Errors**: Ensure your server is accessible from the internet and that any firewalls allow traffic on port 5000 (or your configured port).
2. **Authentication Errors**: Check that the JWT token is being properly generated and validated.
3. **JIT Enablement Failures**: Verify that PyMobileDevice3 is properly installed and configured.

### Logs

Check the server logs for detailed error information:

```bash
# For Docker
docker logs <container_id>

# For Heroku
heroku logs --tail

# For AWS Elastic Beanstalk
eb logs
```

## Updating the Backend

When updating the backend:

1. Make your changes to the code
2. Test locally
3. Deploy using the same method as the initial deployment
4. Monitor logs to ensure the update was successful

## Support

If you encounter issues with the backend, please open an issue on the GitHub repository with detailed information about the problem, including:

- Error messages
- Server logs
- SideStore version
- iOS version
- Deployment environment
