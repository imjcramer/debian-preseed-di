#!/bin/sh
# Desktop role orchestrator. This file is sourced from hooks/role/desktop/late_command.sh.

desktop_log() {
  installer_append_log_category desktop target_customization info desktop "$*" || true
  installer_append_log_category late target_customization info desktop "$*" || true
}

desktop_log_policy_context() {
  desktop_log "policy default_target=${LABWC_DESKTOP_DEFAULT_TARGET:-graphical.target} session=${LABWC_DESKTOP_SESSION_NAME:-Labwc} workspaces=${LABWC_WORKSPACE_COUNT:-4}"
  desktop_log "policy outputs=${LABWC_OUTPUT_POLICY:-external-only} detected=${LABWC_DETECTED_OUTPUTS:-none} internal=${LABWC_DETECTED_INTERNAL_OUTPUTS:-none} external=${LABWC_DETECTED_EXTERNAL_OUTPUTS:-none} primary=${LABWC_DETECTED_PRIMARY_OUTPUT:-none}"
  desktop_log "policy enables waybar=${LABWC_ENABLE_WAYBAR:-true} kanshi=${LABWC_ENABLE_KANSHI:-true} mako=${LABWC_ENABLE_MAKO:-true} swayidle=${LABWC_ENABLE_SWAYIDLE:-true} swaybg=${LABWC_ENABLE_SWAYBG:-true} polkit=${LABWC_ENABLE_POLKIT_AGENT:-true} portal=${LABWC_ENABLE_XDG_DESKTOP_PORTAL:-true} dock=${LABWC_ENABLE_CRYSTAL_DOCK:-true}"
  desktop_log "policy commands launcher=${LABWC_LAUNCHER_COMMAND:-labwc-wofi --show drun} menu=${LABWC_MENU_COMMAND:-labwc-wofi --show drun} file_manager=${LABWC_FILE_MANAGER_COMMAND:-thunar} terminal=${LABWC_TERMINAL_PRIMARY:-foot}/${LABWC_TERMINAL_FALLBACK:-kitty} brightness=${LABWC_BRIGHTNESS_CONTROL_COMMAND:-labwc-brightness-control} power=${LABWC_POWER_SETTINGS_COMMAND:-labwc-power-settings}"
}

run_desktop_late_command() {
  requested_seed_base=${1:-}
  requested_host_profile=${2:-}

  [ "${INSTALLER_HOST_VARIANT:-}" = desktop ] || {
    installer_info "desktop late command skipped for host variant: ${INSTALLER_HOST_VARIANT:-unset}"
    return 0
  }

  desktop_log "loaded desktop env host_profile=${requested_host_profile:-$HOST_PROFILE} account_user=${ACCOUNT_USERNAME:-unset} account_home=${ACCOUNT_HOME:-unset}"
  desktop_policy_enabled || {
    installer_info "Labwc desktop policy disabled by LABWC_DESKTOP_ENABLE"
    desktop_log "skipped Labwc desktop role because LABWC_DESKTOP_ENABLE=${LABWC_DESKTOP_ENABLE:-unset}"
    return 0
  }

  installer_info "installing Labwc desktop role very late for host profile ${requested_host_profile:-$HOST_PROFILE}"
  desktop_log "start Labwc desktop role host_profile=${requested_host_profile:-$HOST_PROFILE}"
  desktop_validate_policy_env
  desktop_log "validated Labwc desktop policy"
  desktop_preflight_required_cmdline_tokens
  desktop_detect_connected_drm_outputs
  desktop_log "detected_outputs=${LABWC_DETECTED_OUTPUTS:-none} primary=${LABWC_DETECTED_PRIMARY_OUTPUT:-none}"
  desktop_resolve_greeter_user
  desktop_log "resolved_greeter_user=${LABWC_GREETER_USER}"
  desktop_configure_greeter_access
  desktop_log_policy_context
  desktop_stage_target_assets
  desktop_log "staged Labwc desktop target assets"
  desktop_render_greetd_config
  desktop_write_default_config
  desktop_install_primary_account_slice_limits
  desktop_log "rendered Labwc desktop defaults and greetd config"
  desktop_install_user_config
  desktop_enable_target_services
  desktop_log "staged Labwc desktop service enablement"
  desktop_log "skipped Labwc desktop target staging verification during installer late-command"
  installer_info "Labwc desktop role installation completed for seed ${requested_seed_base:-$SEED_BASE}"
}
