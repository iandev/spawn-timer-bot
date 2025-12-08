BOT.command(:earthquake) do |event, *args|
  command_quake(event, *args)
end

BOT.command(:quake) do |event, *args|
  command_quake(event, *args)
end

def command_quake(event, *args)
  everyone_alert = USE_EVERYONE_ALERT ? "@everyone " : ""

  return if event.channel.id != COMMAND_CHANNEL_ID

  if args.empty?
    output = []
    output << "```"
    output << "Clears TODs for all timers with a TOD before the specified time. If no time is specified, it will clear all timers with a TOD."
    output << ""
    output << "!quake [time]"
    output << ""
    output << "Examples:"
    output << ""
    output << "!quake 2 hours ago"
    output << "!quake last friday at 9pm"
    output << "!quake now"
    output << "```"
    event.respond(output.join("\n"))
    return
  end

  time_string = args.join(" ")
  earthquake_time = if time_string.to_s.length > 0
    TimeParser.parse(time_string.to_s)
  elsif time_string.to_s.strip.downcase == "now"
    Time.now
  end

  if earthquake_time.to_s.length == 0
    event.user.pm "Could not parse the time '#{time_string}' for the earthquake command."
    return
  end

  timers_to_clear = Timer.where(Sequel.lit('last_tod IS NOT NULL AND last_tod < ?', earthquake_time.to_f))
  cleared_timers_count = timers_to_clear.count

  if cleared_timers_count > 0
    timers_to_clear.update(
      last_tod: nil,
      alerted: false,
      alerting_soon: false,
      skip_count: 0
    )
    update_timers_channel
  end

  response_message = if cleared_timers_count > 0
                       "Quake has been registered! #{cleared_timers_count} timers cleared with TODs before #{earthquake_time.in_time_zone(ENV["TZ"]).strftime("%A, %B %d at %I:%M:%S %p %Z")}."
                     else
                       "Quake has been registered! No timers found with TODs before #{earthquake_time.in_time_zone(ENV["TZ"]).strftime("%A, %B %d at %I:%M:%S %p %Z")}."
                     end

  event.respond response_message

  BOT.send_message(TIMER_ALERT_CHANNEL_ID, "#{everyone_alert}**QUAKE**")
  if defined? (EARTHQUAKE_ALERT_CHANNEL_ID) && EARTHQUAKE_ALERT_CHANNEL_ID.to_s.strip.length > 0
    # earthquake alert channel is defined, so send the EARTHQUAKE_ALERT_MESSAGE if defined, otherwise send the default alert message
    BOT.send_message(EARTHQUAKE_ALERT_CHANNEL_ID, EARTHQUAKE_ALERT_MESSAGE.nil? ? "QUAKE" : EARTHQUAKE_ALERT_MESSAGE)
  end
end
