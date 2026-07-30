#!/bin/sh
# Obtain and renew the TLS certificate, in the same container as the nginx that
# serves it. Started in the background by docker-entrypoint.sh when
# TLS_MODE=acme; nginx stays pid 1.
#
# Shape borrowed from nginxproxy/acme-companion's service loop: poll rather than
# schedule, re-exec rather than loop internally, and keep the sleep interruptible.
# What is NOT borrowed is its docker socket — acme-companion is a separate
# container and reaches nginx through `docker kill -s HUP`, which means mounting
# the socket next to a network-exposed service and handing root over the host to
# whatever compromises it. Running here, the loop signals its own pid 1.
#
# Why polling is free: `lego run` decides for itself whether anything is due —
# it renews when a third of the certificate's lifetime remains (or earlier if the
# CA's RFC 9773 renewalInfo endpoint says so), and exits 0 having done nothing
# otherwise. So ~1400 wake-ups a year cost one cheap decision each, and there is
# no renewal date of our own to get wrong.
set -u

state="${TLS_ACME_STATE:-/var/lib/acme}"
webroot="${TLS_ACME_WEBROOT:-/var/lib/acme/webroot}"
interval="${TLS_ACME_POLL_INTERVAL:-3600}"
name="${TLS_SERVER_NAME:-}"
email="${TLS_ACME_EMAIL:-}"

log() { echo "acme: $*" >&2; }

# Every lego flag has a $LEGO_* equivalent, which is the tidier way to pass an
# optional one: `${VAR:+--server "$VAR"}` in a command line leaves the quoting of
# the value ambiguous, and this avoids the question entirely. Staging and an
# internal step-ca are both just a different directory URL.
if [ -n "${TLS_ACME_SERVER:-}" ]; then
    LEGO_SERVER="$TLS_ACME_SERVER"
    export LEGO_SERVER
fi

if [ -z "$name" ] || [ "$name" = "_" ]; then
    log "TLS_SERVER_NAME is not a hostname; refusing to ask a CA for '$name'"
    exit 1
fi
if [ -z "$email" ]; then
    log "TLS_ACME_EMAIL is unset; a CA account needs a contact address"
    exit 1
fi

# Do not ask a CA to validate a challenge nothing is listening to serve. The loop
# is started before nginx is exec'd, so on a cold start the listener may be a
# moment away; a failed first attempt would otherwise cost a whole poll interval.
#
# netstat, not nc: this image's busybox is built without the nc applet (and
# without wget), and ash has no /dev/tcp. netstat -lnt is what is actually
# available, and it reads the container's own netns, which is the one that
# matters. The smoke test asserts the applet exists so this cannot rot silently.
wait_for_nginx() {
    i=0
    while [ "$i" -lt 60 ]; do
        if netstat -lnt 2>/dev/null | grep -q ':8080[[:space:]]'; then
            return 0
        fi
        i=$((i + 1))
        sleep 1
    done
    log "nginx is not listening on :8080 after 60s; trying anyway"
    return 0
}

attempt() {
    # --http.webroot rather than lego's own listener: nginx already owns :80, and
    # this writes the challenge file into a directory nginx serves instead.
    # --no-random-sleep because our schedule is already spread — the poll phase is
    # set by container start time, not by a wall-clock cron everyone shares.
    # --renew-days is deliberately unset: lego derives the window from the
    # certificate's own lifetime, which stays right if the CA shortens it.
    lego \
        --accept-tos \
        --email "$email" \
        --domains "$name" \
        --path "$state" \
        --http --http.webroot "$webroot" \
        --no-random-sleep \
        --deploy-hook /usr/local/bin/acme-deploy.sh \
        run
}

# Rate limits punish a restart loop: Let's Encrypt allows 5 failed validations per
# hostname per hour, and `restart: always` plus a container that dies for an
# unrelated reason is one attempt per restart. A timestamp in the state volume
# turns that into one attempt per window however often we are restarted.
too_soon() {
    marker="$state/.last-attempt"
    [ -f "$marker" ] || return 1
    now=$(date -u +%s)
    then_=$(cat "$marker" 2>/dev/null || echo 0)
    [ $((now - then_)) -lt "${TLS_ACME_MIN_RETRY:-300}" ]
}
mark_attempt() { date -u +%s > "$state/.last-attempt" 2>/dev/null || true; }

trap '[ -n "${pid:-}" ] && kill "$pid" 2>/dev/null; exec "$0"' EXIT
trap 'trap - EXIT' INT TERM

wait_for_nginx

if too_soon; then
    log "an attempt was made less than ${TLS_ACME_MIN_RETRY:-300}s ago; skipping this pass"
else
    mark_attempt
    if attempt; then
        log "lego reports the certificate for $name is current"
    else
        log "lego failed for $name; retrying at the next pass"
    fi
fi

# Backgrounded plus `wait` so a signal is acted on now rather than up to an hour
# from now. (Container stop does not depend on this — the runtime signals pid 1,
# which is nginx, and teardown takes this process with it — but a direct kill of
# the loop should still be prompt.)
sleep "$interval" & pid=$!
wait
pid=
