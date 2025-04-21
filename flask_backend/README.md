# SideStore JIT Backend

This is a Flask-based backend for enabling JIT (Just-In-Time) compilation for apps installed via SideStore on iOS devices. It replaces the need for git-based JIT enablement methods and provides a unified API for both iOS 16 and iOS 17+ devices.

## Features

- Secure device registration with JWT authentication
- JIT enablement for iOS 16 and below
- JIT enablement for iOS 17+
- Session tracking for JIT operations
- Health check endpoint
- Device management

## Requirements

- Python 3.8+
- Flask
- Flask-JWT-Extended
- Flask-CORS
- PyMobileDevice3
- Gunicorn (for production)

## Installation

1. Clone this repository
2. Install dependencies:
   ```
   pip install -r requirements.txt
   ```

## Development

Run the development server:

```bash
export FLASK_ENV=development
export FLASK_APP=app.py
flask run --host=0.0.0.0 --port=5000
```

## Production Deployment

### Using Docker

1. Build the Docker image:
   ```
   docker build -t sidestore-jit-backend .
   ```

2. Run the container:
   ```
   docker run -d -p 5000:5000 -e JWT_SECRET_KEY=your_secret_key sidestore-jit-backend
   ```

### Using Gunicorn

1. Set environment variables:
   ```
   export JWT_SECRET_KEY=your_secret_key
   ```

2. Run with Gunicorn:
   ```
   gunicorn --bind 0.0.0.0:5000 --workers 4 production_app:app
   ```

## API Endpoints

### Health Check
- `GET /health`
  - Returns the health status of the server

### Device Registration
- `POST /register`
  - Registers a device and returns a JWT token
  - Request body: `{"udid": "device_udid", "device_name": "iPhone"}`
  - Response: `{"token": "jwt_token", "message": "Device registered successfully"}`

### Enable JIT
- `POST /enable-jit`
  - Enables JIT for a specific app
  - Requires JWT authentication
  - Request body: `{"bundle_id": "com.example.app", "ios_version": "16.5"}`
  - Response: `{"status": "JIT enabled", "session_id": "uuid", "message": "Enabled JIT for 'com.example.app'!"}`

### Session Status
- `GET /session/<session_id>`
  - Gets the status of a JIT enablement session
  - Requires JWT authentication
  - Response: `{"status": "completed", "started_at": 1617293932, "bundle_id": "com.example.app"}`

### Device Statistics
- `GET /devices`
  - Gets statistics about registered devices and active sessions
  - Response: `{"registered_devices": 10, "active_sessions": 5}`

## Security Considerations

- In production, always use HTTPS
- Set a strong JWT_SECRET_KEY
- Consider implementing rate limiting
- Use a proper database for device and session storage
- Implement proper access controls for admin endpoints

## License

This project is licensed under the MIT License - see the LICENSE file for details.
