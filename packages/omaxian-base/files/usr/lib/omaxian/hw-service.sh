# Omaxian OS: shared start/stop logic for the hardware helper daemons that
# Debian only ships as systemd units (sourced by /etc/init.d/omaxian-*).
# The init script sets NAME, DESC, DAEMON, DAEMON_ARGS and defines
# omx_hw_present (exit 0 when this machine has the hardware), then calls
#   omx_hw_service "$@"
# The daemons run in the foreground (systemd Type=dbus); start-stop-daemon
# backgrounds them and keeps the pid file. Missing daemon or missing
# hardware: start is a clean no-op (no startpar failure at boot).
# shellcheck shell=sh

# shellcheck source=/dev/null
. /lib/lsb/init-functions

PIDFILE=/run/$NAME.pid

omx_hw_service() {
	case "$1" in
	start)
		[ -x "$DAEMON" ] || exit 0
		if ! omx_hw_present; then
			log_action_msg "$DESC: no matching hardware, not started" || true
			exit 0
		fi
		log_daemon_msg "Starting $DESC" "$NAME" || true
		# shellcheck disable=SC2086
		if start-stop-daemon --start --quiet --oknodo --background --make-pidfile \
			--pidfile "$PIDFILE" --exec "$DAEMON" -- $DAEMON_ARGS; then
			log_end_msg 0 || true
		else
			log_end_msg 1 || true
		fi
		;;
	stop)
		log_daemon_msg "Stopping $DESC" "$NAME" || true
		if start-stop-daemon --stop --quiet --oknodo --retry 5 --pidfile "$PIDFILE" --exec "$DAEMON"; then
			rm -f "$PIDFILE"
			log_end_msg 0 || true
		else
			log_end_msg 1 || true
		fi
		;;
	restart|force-reload)
		"$0" stop
		"$0" start
		;;
	status)
		status_of_proc -p "$PIDFILE" "$DAEMON" "$NAME" && exit 0 || exit $?
		;;
	*)
		echo "Usage: $0 {start|stop|restart|force-reload|status}" >&2
		exit 3
		;;
	esac
	exit 0
}

# true when running under a hypervisor (CPU "hypervisor" flag)
omx_in_vm() { grep -qw hypervisor /proc/cpuinfo 2>/dev/null; }
