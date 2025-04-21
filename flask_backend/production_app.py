from flask import Flask, request, jsonify
from flask_jwt_extended import JWTManager, create_access_token, jwt_required, get_jwt_identity
from flask_cors import CORS
import os
import logging
import uuid
import json
from datetime import timedelta
import time
import threading
from pymobiledevice3.lockdown import LockdownClient

# Import our compatibility module instead of the missing module
try:
    # Try to import the original module first
    from pymobiledevice3.services.debugserver import DebugServerService
    logging.info("Using original pymobiledevice3.services.debugserver module")
except ImportError:
    # If it fails, use our compatibility module
    from flask_backend.pymobiledevice3_compat.debugserver import DebugServerService
    logging.info("Using compatibility pymobiledevice3_compat.debugserver module")

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

# Lock for thread safety when accessing shared data
device_lock = threading.Lock()
session_lock = threading.Lock()

class JITEnabler:
    @staticmethod
    def enable_jit_ios16(udid, bundle_id):
        """Enable JIT for iOS 16 and below using pymobiledevice3"""
        try:
            logger.info(f"Enabling JIT for iOS 16 device {udid}, app {bundle_id}")
            
            # Connect to the device
            lockdown = LockdownClient(udid=udid)
            debug_service = DebugServerService(lockdown)
            
            # Enable JIT for the app
            debug_service.enable_jit(bundle_id)
            
            logger.info(f"JIT enabled successfully for {bundle_id} on device {udid}")
            return True
        except Exception as e:
            logger.error(f"Error enabling JIT for iOS 16 device: {str(e)}")
            return False
    
    @staticmethod
    def enable_jit_ios17(udid, bundle_id):
        """Enable JIT for iOS 17+ using pymobiledevice3"""
        try:
            logger.info(f"Enabling JIT for iOS 17 device {udid}, app {bundle_id}")
            
            # Connect to the device
            lockdown = LockdownClient(udid=udid)
            debug_service = DebugServerService(lockdown)
            
            # Enable JIT for the app (iOS 17 method)
            # Note: The actual implementation might differ based on pymobiledevice3 capabilities
            debug_service.enable_jit(bundle_id)
            
            logger.info(f"JIT enabled successfully for {bundle_id} on device {udid}")
            return True
        except Exception as e:
            logger.error(f"Error enabling JIT for iOS 17 device: {str(e)}")
            return False

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
    with device_lock:
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
    with device_lock:
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
        with session_lock:
            active_jit_sessions[session_id] = {
                'udid': udid,
                'bundle_id': bundle_id,
                'started_at': time.time(),
                'status': 'processing'
            }
        
        # Enable JIT based on iOS version
        if ios_version.startswith('17'):
            # iOS 17+ method
            success = JITEnabler.enable_jit_ios17(udid, bundle_id)
        else:
            # iOS 16 and below method
            success = JITEnabler.enable_jit_ios16(udid, bundle_id)
        
        with session_lock:
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
    with session_lock:
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
    with device_lock, session_lock:
        return jsonify({
            'registered_devices': len(registered_devices),
            'active_sessions': len(active_jit_sessions)
        }), 200

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    debug = os.environ.get('FLASK_ENV') == 'development'
    
    logger.info(f"Starting SideStore JIT Backend on port {port}")
    app.run(host='0.0.0.0', port=port, debug=debug, ssl_context='adhoc')
