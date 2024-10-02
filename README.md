## Celestia Bridge Healthcheck Script

This repository contains a healthcheck script for Celestia Bridge nodes with integrated support for [Healthchecks.io](https://healthchecks.io/).

### How It Works

1. The script performs a series of health checks (service availability, log checks and DA state checks).
2. Reports the status to Healthchecks.io using your unique check URL.
3. Use as a cron job or integrate into CI/CD pipelines for automated monitoring.

### Getting Started

1. Create your project and obtain an API key from https://healthchecks.io/
2. Download the script:
```
wget -O $HOME/celestia_da_monitor.sh https://raw.githubusercontent.com/NodesGuru/celestia-bridge-healthcheck/refs/heads/main/celestia_da_monitor.sh
```
3. Set up your Healthchecks.io check URL in the script (edit `HC_API_KEY` field with the key from healthchecks.io):
```
nano $HOME/celestia_da_monitor.sh
```
4. Execute the script or schedule it with a cron job:
```
crontab -e
# Add this to the end
*/1 * * * * /bin/bash $HOME/celestia_da_monitor.sh >> $HOME/celestia_da_monitor.log
```

### Requirements

- Bash
- Celestia Bridge node
- https://healthchecks.io/ key
