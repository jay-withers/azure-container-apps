locals {
  # The workspace's ingestion cap, held here rather than inline on the resource
  # only so the alert that watches it reads the same number. A threshold that
  # drifted from the cap would warn late or never.
  #
  # Note this cap is now **shared across every tenant**. Reaching it stops
  # ingestion for all of them for the rest of the day, which is the one failure
  # that blinds everything else here — including the job-failure alert, which
  # reads logs rather than metrics. Measured ingestion on the existing
  # market-agent deployment is ~0.0005 GB/day, so this sits far above normal use
  # and exists to catch a runaway (a crash-looping replica logging at speed).
  log_daily_quota_gb = 0.15

  # Fired at, not on: warning while there is still a day's headroom left is the
  # only useful moment, since hitting the cap is what stops the logs that would
  # tell you about it.
  log_quota_alert_gb = local.log_daily_quota_gb * 0.8
}
