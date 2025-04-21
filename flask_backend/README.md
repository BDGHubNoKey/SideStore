# SideStore Flask Backend

This is the Flask backend for SideStore, which provides JIT enablement for iOS apps.

## Setup

1. Install the required dependencies:
   ```
   pip install -r requirements.txt
   ```

2. Run the server:
   ```
   python production_app.py
   ```

## Important Notes

### pymobiledevice3 Compatibility

The backend requires specific versions of dependencies to work correctly:

- `pymobiledevice3==2.30.0`: Version 2.31.0+ breaks the JIT functionality due to changes in the API.
- `construct==2.10.69`: Required for pymobiledevice3 2.30.0 to work properly. Newer versions cause 'stream.tell()' errors.

If you encounter the error `ModuleNotFoundError: No module named 'pymobiledevice3.services.debugserver'`, the backend will automatically use a compatibility module that implements the missing functionality.

### Compatibility Module

The `pymobiledevice3_compat` directory contains a compatibility layer that implements the missing `debugserver` module. This allows the backend to work with newer versions of pymobiledevice3 if needed, although it's still recommended to use the pinned versions in requirements.txt.

## API Endpoints

- `/health`: Check if the server is running
- `/register`: Register a device
- `/enable-jit`: Enable JIT for an app
- `/session/<session_id>`: Get the status of a JIT enablement session
- `/devices`: List registered devices and active sessions

## Troubleshooting

If you encounter issues with JIT enablement:

1. Make sure you're using the correct versions of pymobiledevice3 and construct:
   ```
   pip install pymobiledevice3==2.30.0 construct==2.10.69
   ```

2. If you're using a system-wide Python installation, you might need to use the specific Python executable:
   ```
   /Library/Developer/CommandLineTools/usr/bin/python3 -m pip install pymobiledevice3==2.30.0 construct==2.10.69
   ```

3. Check the logs for detailed error messages.
