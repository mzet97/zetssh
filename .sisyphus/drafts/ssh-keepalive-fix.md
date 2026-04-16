# Draft: SSH Keepalive / Connection Drop on Screen Lock

## Requirements (confirmed)
- Fix SSH connection dropping when user locks screen or stays idle
- User's exact words: "ele fecha a conexao se eu bloquio a tela ou fico muito tempo sem mechcer no ssh"

## Root Cause Analysis

### Problem: 3 contributing factors

**Factor 1: SSHKeepaliveHandler is PASSIVE (not ACTIVE)**
- `RealSSHEngine.swift:682-741` — The `SSHKeepaliveHandler` only DETECTS dead connections
- Every 60s it increments a counter; resets only on `channelRead` (data received from server)
- After 3 intervals (180s), it closes the connection with `connectionTimedOut`
- It NEVER sends keepalive data to the server to PREVENT the connection from dying

**Factor 2: TCP KeepAlive not configured properly**
- `RealSSHEngine.swift:160` — `.channelOption(ChannelOptions.socketOption(.so_keepalive), value: 1)`
- Only enables TCP keepalive, but macOS default `TCP_KEEPALIVE` interval is 7200s (2 HOURS)
- No `TCP_KEEPINTVL` or `TCP_KEEPCNT` configured
- This means TCP-level keepalive won't save connections for short idle periods

**Factor 3: No App Nap prevention**
- When macOS screen locks, the system throttles/suspends background app timers
- The NIO EventLoop scheduled tasks (`scheduleRepeatedTask`) may not fire
- Network sockets may be affected by power management
- No `ProcessInfo.beginActivity` or `NSProcessInfo.disableAutomaticTermination` calls anywhere in codebase

### Flow when the bug occurs:
1. User locks screen → macOS throttles app → EventLoop timers don't fire
2. TCP connection silently dies (NAT/firewall timeout, or server idle timeout)
3. When app resumes, `SSHKeepaliveHandler` fires, detects no data received in 3 intervals
4. Closes connection → calls `delegate?.onError(connectionTimedOut)` → UI shows disconnect message

## Technical Decisions
- [DECIDED] Auto-reconnect: YES with notification banner before reconnecting
- [DECIDED] Keepalive method: Active keepalive via SSH keepalive requests + TCP keepalive tuning + App Nap prevention
- [DEFAULT] Keepalive interval: 60s (already set), no UI setting needed for now

## Research Findings
- `SSHKeepaliveHandler` in `RealSSHEngine.swift:682-741` — passive keepalive, only detects
- `ClientBootstrap` in `RealSSHEngine.swift:158-173` — only sets `SO_KEEPALIVE=1`
- SwiftNIO-SSH doesn't have built-in keepalive request API
- macOS TCP_KEEPALIVE socket option can be set via `ChannelOptions.socketOption(.tcp_keepalive)` on macOS
- `ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason:)` prevents App Nap

## Open Questions
- None remaining - all decisions made

## Scope Boundaries
- INCLUDE: Fix connection drop on screen lock, fix connection drop on idle
- EXCLUDE: SFTP keepalive (separate concern), UI redesign, new features
