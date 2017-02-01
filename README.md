# fluent-plugin-notifier

[Fluentd](http://fluentd.org) plugin to emit notifications for messages, with numbers over/under threshold, or specified pattern strings.

## Configuration

To notify apache logs with over 1000000 (microseconds) duration for CRITICAL , or status '500' by string pattern match:

    <match apache.log.**>
      @type notifier
      @label @notification_events
      <def>
        pattern apache_duration
        check numeric_upward
        warn_threshold  800000
        crit_threshold 1000000
        target_keys duration
      </def>
      <def>
        pattern status_500
        check string_find
        warn_regexp 5\d\d
        crit_regexp 500
        target_key_pattern ^status.*$
        exclude_key_pattern ^status_ignore_.*$  # key name not to notify about...
      </def>
    </match>

With this configuration, you will get notification messages in `<label @notification_events>` section, like this:

    2012-05-15 19:44:29 +0900 notification: {"pattern":"apache_duration","target_tag":"apache.log.xxx","target_key":"duration","check_type":"numeric_upward","level":"crit","threshold":1000000,"value":"1057231","message_time":"2012-05-15 19:44:27 +0900"}
    2012-05-15 19:44:29 +0900 notification: {"pattern":"status_500","target_tag":"apache.log.xxx","target_key":"status","check_type":"string_find","level":"crit","regexp":"/500/","value":"500","message_time":"2012-05-15 19:44:27 +0900"}

Available 'check' types: 'numeric\_upward', 'numeric\_downward' and 'string\_find'

Default configurations:

* tag: 'notification'
  * in <match> top level, 'default\_tag', 'default\_tag\_warn,' and 'default\_tag\_crit' available
  * in each <def> section, 'tag', 'tag\_warn' and 'tag\_crit' available
* notification suppression
  * at first, notified once in 1 minute, 5 times
  * next, notified once in 5 minutes, 5 times
  * last, notified once in 30 minutes
  * in <match> top level, 'default\_interval\_1st', 'default\_interval\_2nd', 'default\_interval\_3rd', 'default\_repetitions\_1st' and 'default\_repetitions\_2nd' available
  * in each <def> section, 'interval\_1st', 'interval\_2nd', 'interval\_3rd', 'repetitions\_1st' and 'repetitions\_2nd' available

If you want to get every 5 minutes notifications (after 1 minutes notifications), specify '0' for 'repetitions\_2nd'.

### Message Testing

To include specified messages into check target, or to exclude specified messages from check target, <test> directive is useful.

    <match apache.log.**>
      @type notifier
      @label @notifications
      <test>
        check numeric
        target_key duration     # microseconds
        lower_threshold 5000    # 5ms
        upper_threshold 5000000 # 5s
      </test>
      <def>
        pattern status_500
        check string_find
        warn_regexp 5\d\d
        crit_regexp 500
        target_key_pattern ^status.*$
      </def>
    </match>
    
    <label @notifications>
      <match **>
        # send notifications to Slack, email or ...
      </match>
    </label>

With configuration above, fluent-plugin-notifier checks messages with specified duration value (d: 5000 <= d <= 5000000), and others are ignored.

Available 'check' types are: 'numeric', 'regexp' and 'tag'.

* numeric
  * 'lower\_threshold', 'upper\_threshold' and both are available
* regexp, tag
  * 'include\_pattern', 'exclude\_pattern' and both are available
  * 'tag' checks tag strings after 'input\_tag\_remove\_prefix'

Multiple <test> directives means logical AND of each tests.

    <match apache.log.**>
      @type notifier
      @label @notifications
      input_tag_remove_prefix apache.log
      <test>
        check tag
        include_pattern ^news[123]$ # for specified web server log
      </test>
      <test>
        check numeric
        target_key duration     # microseconds
        lower_threshold 5000    # 5ms
      </test>
      <test>
        check regexp
        target_key vhost
        exclude_pattern ^image.news.example.com$  # ingore image delivery server log
      </test>
      <test>
        check regexp
        target_key path
        include_pattern ^/path/to/contents/    # for specified content path only
        exclude_pattern \.(gif|jpg|png|swf)$   # but image files are ignored
      </test>
      <def>
        pattern status_500
        check string_find
        warn_regexp 5\d\d
        crit_regexp 500
        target_key_pattern ^status.*$
      </def>
    </match>

Notifier plugin configured like this will check messages:
 * with tag 'apache.log.news1', 'apache.log.news2' or 'apache.log.news3'
 * with duration bigger than 5ms (upper unlimited)
 * without vhost image.news.example.com
 * with request path '/path/to/contents/*' and without file suffix gif/jpg/png/swf.

## TODO

* patches welcome!

## Copyright

* Copyright
  * Copyright (c) 2012- TAGOMORI Satoshi (tagomoris)
* License
  * Apache License, Version 2.0
