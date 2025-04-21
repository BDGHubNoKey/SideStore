func enableJIT(for installedApp: InstalledApp) {
        // Check if JIT API URL is configured
        let jitAPIURL = UserDefaults.standard.string(forKey: "jit_api_base_url")
        
        if jitAPIURL == nil {
            // Show alert to configure JIT API URL
            let alert = UIAlertController(title: "JIT API Not Configured", 
                                         message: "Please configure the JIT API URL in Settings before enabling JIT.", 
                                         preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alert, animated: true, completion: nil)
            return
        }
        
        AppManager.shared.enableJIT(for: installedApp) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    break
                case .failure(let error):
                    ToastView(error: error, opensLog: true).show(in: self)
                    AppManager.shared.log(error, operation: .enableJIT, app: installedApp)
                }
            }
        }
    }
