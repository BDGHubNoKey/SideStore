from flask import Flask, request, jsonify
from flask_jwt_extended import JWTManager, create_access_token, jwt_required, get_jwt_identity
from flask_cors import CORS
import os
import logging
import uuid
import json
from datetime import timedelta
import subprocess
import threading
import time

# Configure logging
logging.basicConfig(level=logging.INFO, 
                    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

# Configure JWT
app.config['JWT_SECRET_KEY'] = os.environ.get('JWT_SECRET_KEY', 'dev-secret-key')  # Change in production
app.config['JWT_ACCESS_TOKEN_EXPIRES'] = timedelta(days=30)  # Long-lived tokens for mobile devices
jwt = JWTManager(app)

# In-memory storage for registered devices and active JIT sessions
# In production, use a proper database
registered_devices = {}
active_jit_sessions = {}

# Mock implementation of pymobiledevice3 functionality
# In production, use the actual pymobiledevice3 library
class MockDebugServer:
    @staticmethod
    def enable_jit(udid, bundle_id):
        logger.info(f"Enabling JIT for device {udid}, app {bundle_id}")
        # Simulate JIT enablement
        time.sleep(1)  # Simulate processing time
        return True

# Routes
@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({'status': 'healthy'}), 200

@app.route('/register', methods=['POST'])
def register_device():
    data = request.get_json()
    if not data or 'udid' not in data:
        return jsonify({'error': 'UDID required'}), 400
    
    udid = data['udid']
    device_name = data.get('device_name', 'Unknown Device')
    
    # Generate a token for the device
    access_token = create_access_token(identity=udid)
    
    # Store device info
    registered_devices[udid] = {
        'device_name': device_name,
        'registered_at': time.time(),
        'last_active': time.time()
    }
    
    logger.info(f"Device registered: {udid} ({device_name})")
    return jsonify({
        'token': access_token,
        'message': 'Device registered successfully'
    }), 200

@app.route('/enable-jit', methods=['POST'])
@jwt_required()
def enable_jit():
    # Get the identity from the JWT
    udid = get_jwt_identity()
    
    # Check if device is registered
    if udid not in registered_devices:
        return jsonify({'error': 'Device not registered'}), 401
    
    # Update last active timestamp
    registered_devices[udid]['last_active'] = time.time()
    
    data = request.get_json()
    if not data or 'bundle_id' not in data:
        return jsonify({'error': 'Bundle ID required'}), 400
    
    bundle_id = data['bundle_id']
    ios_version = data.get('ios_version', 'unknown')
    
    # Log the request
    logger.info(f"JIT enablement request: Device {udid}, App {bundle_id}, iOS {ios_version}")
    
    try:
        # Create a unique session ID for this JIT enablement
        session_id = str(uuid.uuid4())
        
        # Store session info
        active_jit_sessions[session_id] = {
            'udid': udid,
            'bundle_id': bundle_id,
            'started_at': time.time(),
            'status': 'processing'
        }
        
        # Enable JIT based on iOS version
        if ios_version.startswith('17'):
            # iOS 17+ method
            logger.info(f"Using iOS 17+ method for device {udid}")
            success = MockDebugServer.enable_jit(udid, bundle_id)
        else:
            # iOS 16 and below method
            logger.info(f"Using iOS 16 method for device {udid}")
            success = MockDebugServer.enable_jit(udid, bundle_id)
        
        if success:
            active_jit_sessions[session_id]['status'] = 'completed'
            return jsonify({
                'status': 'JIT enabled',
                'session_id': session_id,
                'message': f"Enabled JIT for '{bundle_id}'!"
            }), 200
        else:
            active_jit_sessions[session_id]['status'] = 'failed'
            return jsonify({
                'error': 'Failed to enable JIT',
                'session_id': session_id
            }), 500
            
    except Exception as e:
        logger.error(f"Error enabling JIT: {str(e)}")
        return jsonify({'error': str(e)}), 500

@app.route('/session/<session_id>', methods=['GET'])
@jwt_required()
def get_session_status(session_id):
    if session_id not in active_jit_sessions:
        return jsonify({'error': 'Session not found'}), 404
    
    # Check if the requesting device owns this session
    udid = get_jwt_identity()
    if active_jit_sessions[session_id]['udid'] != udid:
        return jsonify({'error': 'Unauthorized'}), 403
    
    return jsonify({
        'status': active_jit_sessions[session_id]['status'],
        'started_at': active_jit_sessions[session_id]['started_at'],
        'bundle_id': active_jit_sessions[session_id]['bundle_id']
    }), 200

@app.route('/devices', methods=['GET'])
def list_devices():
    # This endpoint would be protected in production
    return jsonify({
        'registered_devices': len(registered_devices),
        'active_sessions': len(active_jit_sessions)
    }), 200

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    debug = os.environ.get('FLASK_ENV') == 'development'
    
    logger.info(f"Starting SideStore JIT Backend on port {port}")
    app.run(host='0.0.0.0', port=port, debug=debug, ssl_context='adhoc')
