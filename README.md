# ossec-server

This is a direct derivative of the excellent work done by Terence Kent <tkent@xetus.com> for xetusoss/ossec-server.  The primary changes are porting to CentOS 6 and adding support for ossec-wui (Web frontend for viewing ossec-hids data).

An ossec-server image with the ability to separate the ossec configuration/data from the container. This image is designed to be as turnkey as possible, supporting out of the box:

1. Automatic enrollment for agents, using ossec-authd
2. Syslog forwarding support for the ossec server messages (requires syslog server)
3. SMTP notifications (requires no-auth SMTP server)
4. Web frontend via Apache and ossec-wui

The following directories are externalized under `/var/ossec/data` to allow the container to be replaced without configuration or data loss: `logs`, `etc`, `stats`,`rules`, and `queue`. In addition to those directories, the `bin/.process_list` file is symlinked to `process_list` in the data volume.

## Quick Start

To get an up and running ossec server that supports auto-enrollment, has a web frontend, and sends HIDS notifications a SYSLOG server, use.

```
 docker run --name ossec-server -d -p 1514:1514/udp -p 1515:1515 -p 443:443/tcp \
  -e SYSLOG_FORWADING_ENABLED=true -e SYSLOG_FORWARDING_SERVER_IP=X.X.X.X \
  -e WEB_ENABLED=true -e WEB_USER=admin -e WEB_PASSWORD=supersecure \
  -v /somepath/ossec_mnt:/var/ossec/data delder/ossec-server
```

Once the system starts up, you can execute the standard ossec commands using docker. For example, to list active agents.

```
docker exec -ti ossec-server /var/ossec/bin/list_agents -a
```

## Available Configuration Parameters

* __AUTO_ENROLLMENT_ENABLED__: Specifies whether or not to enable auto-enrollment via ossec-authd. Defaults to `true`;
* __AUTHD_OPTIONS__: Options to passed ossec-authd, other than -p and -g. Defaults to empty;
* __SMTP_ENABLED__: Whether or not to enable SMTP notifications. Defaults to `true` if ALERTS_TO_EMAIL is specified, otherwise `false`
* __SMTP_RELAY_HOST__: The relay host for SMTP messages, required for SMTP notifications. This host must support non-authenticated SMTP ([see this thread](https://ossec.uservoice.com/forums/18254-general/suggestions/803659-allow-full-confirguration-of-smtp-service-in-ossec)). No default.
* __ALERTS_FROM_EMAIL__: The email address the alerts should come from. Defaults to `ossec@$HOSTNAME`.
* __ALERTS_TO_EMAIL__: The destination email address for SMTP notifications, required for SMTP notifications. No default.
* __SYSLOG_FORWADING_ENABLED__: Specify whether syslog forwarding is enabled or not. Defaults to `false`.
* __SYSLOG_FORWARDING_SERVER_IP__: The IP for the syslog server to send messagse to, required for syslog fowarding. No default.
* __SYSLOG_FORWARDING_SERVER_PORT__: The destination port for syslog messages. Default is `514`.
* __SYSLOG_FORWARDING_FORMAT__: The syslog message format to use. Default is `default`.
* __WEB_ENABLED__: Whether to turn on Apache to enable access to ossec-wui at https://hostname/ossec/
* __WEB_USER__: Username to set for htaccess to ossec-wui (defaults to admin if not set)
* __WEB_PASSWORD__: Password to set for WEB_USER access to ossec-wui (defaults to admin if not set)  


**Please note**: All the SMTP, SYSLOG, and WEB configuration variables are only applicable to the first time setup. Once the container's data volume has been initialized, all the configuration options for OSSEC can be changed.

## Known Issues / Warnings

##### A default localhost agent is added

On first launch, the ossec server will not start up properly and bind to port 1514, unless at least one agent to be present in the client.keys file. To avoid that issue, a local agent is setup by default. See [this bug](https://groups.google.com/forum/#!topic/ossec-list/qeC_h3EZCxQ) with OSSEC.
