# 0136. A Cloudflare Worker can host the relay

A self-hosted relay can run in a Cloudflare account without an always-on machine. The Worker serves the same phone build and speaks the rendezvous protocol of ADR 0033, so the daemon and phone take the same relay address as before.

Route each rendezvous ID to one Durable Object. This puts both ends of a connection in the same place and lets unrelated pairs run independently. A short handshake may hold the first dialer message in memory. Once the listener is waiting or the peers are paired, Cloudflare can hibernate the object while keeping its sockets. The socket attachments carry the pairing and rate counters across hibernation. The object uses a storage alarm for the waiting listener's expiry.

This adds a second implementation of the wire protocol. Exercise it with the existing Go relay client and Noise transport. Keep the Go server for operators who control their own host.
