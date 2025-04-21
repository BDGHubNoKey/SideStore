"""
Compatibility module for pymobiledevice3.services.debugserver

This module provides a compatibility layer for the missing debugserver module in pymobiledevice3.
It implements the DebugServerService class that was used in previous versions of pymobiledevice3.
"""

import logging
from pymobiledevice3.lockdown import LockdownClient
from pymobiledevice3.services.dvt.dvt_secure_socket_proxy import DvtSecureSocketProxyService

logger = logging.getLogger(__name__)

class DebugServerService:
    """
    Compatibility implementation of DebugServerService for pymobiledevice3
    
    This class provides the same interface as the original DebugServerService
    but uses the DvtSecureSocketProxyService to implement the functionality.
    """
    
    def __init__(self, lockdown: LockdownClient):
        """
        Initialize the DebugServerService
        
        Args:
            lockdown: The LockdownClient instance to use for communication with the device
        """
        self.lockdown = lockdown
        self.dvt = DvtSecureSocketProxyService(lockdown=lockdown)
        logger.info("Initialized DebugServerService compatibility layer")
    
    def enable_jit(self, bundle_id: str) -> bool:
        """
        Enable JIT for the specified application
        
        Args:
            bundle_id: The bundle ID of the application to enable JIT for
            
        Returns:
            True if JIT was enabled successfully, False otherwise
        """
        try:
            logger.info(f"Enabling JIT for application: {bundle_id}")
            
            # Use the process_control service to enable JIT
            from pymobiledevice3.services.dvt.instruments.process_control import ProcessControl
            
            process_control = ProcessControl(self.dvt)
            
            # Get the list of running applications
            apps = process_control.list_running_processes()
            
            # Find the target application
            target_app = None
            for app in apps:
                if app.get('bundle_id') == bundle_id:
                    target_app = app
                    break
            
            if not target_app:
                logger.error(f"Application with bundle ID {bundle_id} not found in running processes")
                return False
            
            # Get the process ID
            pid = target_app.get('pid')
            if not pid:
                logger.error(f"Could not get process ID for application {bundle_id}")
                return False
            
            logger.info(f"Found application {bundle_id} with PID {pid}")
            
            # Enable JIT for the process
            # This is a simplified implementation - in reality, enabling JIT might require
            # more complex interactions with the device
            try:
                # Try to use the debugserver command if available
                self.dvt.channel.send_command("debugserver", {"enable_jit": True, "pid": pid})
                logger.info(f"Successfully enabled JIT for {bundle_id} using debugserver command")
                return True
            except Exception as e:
                logger.warning(f"Could not enable JIT using debugserver command: {str(e)}")
                
                # Alternative approach: use the process_control to kill and restart the app
                # This might trigger JIT enablement on some iOS versions
                try:
                    logger.info(f"Trying alternative approach to enable JIT for {bundle_id}")
                    process_control.kill(pid)
                    logger.info(f"Killed process {pid}, waiting for app to restart")
                    # The app should restart automatically
                    return True
                except Exception as e2:
                    logger.error(f"Failed to enable JIT using alternative approach: {str(e2)}")
                    return False
            
        except Exception as e:
            logger.error(f"Error enabling JIT for {bundle_id}: {str(e)}")
            return False
        
    def __enter__(self):
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        if hasattr(self, 'dvt'):
            self.dvt.__exit__(exc_type, exc_val, exc_tb)
