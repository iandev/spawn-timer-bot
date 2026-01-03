BOT.command(:earthquake) do |event, *args|
  command_quake(event, *args)
end

BOT.command(:quake) do |event, *args|
  command_quake(event, *args)
end

def command_quake(event, *args)
  everyone_alert = USE_EVERYONE_ALERT ? "@everyone " : ""

  return if event.channel.id != COMMAND_CHANNEL_ID

  if args.first.to_s.downcase == "predict"
    predict_next_quake(event)
    return
  end

  if args.first.to_s.downcase == "chance"
    predict_quake_probability2(event)
    return
  end

  if args.first.to_s.downcase == "list"
    list_recent_quakes(event)
    return
  end

  if args.empty?
    output = []
    output << "```"
    output << "Clears TODs for all timers with a TOD before the specified time. If no time is specified, it will clear all timers with a TOD."
    output << ""
    output << "!quake [time]"
    output << "!quake predict"
    output << "!quake chance"
    output << "!quake list"
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

  Earthquake.create(timestamp: earthquake_time.to_f, created_at: Time.now.utc)

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

def predict_next_quake(event)
  quakes = Earthquake.order(:timestamp).all

  if quakes.count < 2
    event.respond "Not enough data to predict the next quake. Need at least 2 recorded quakes."
    return
  end

  n = quakes.count
  sum_x = 0
  sum_y = 0
  sum_xy = 0
  sum_xx = 0

  quakes.each_with_index do |quake, x|
    y = quake.timestamp
    sum_x += x
    sum_y += y
    sum_xy += (x * y)
    sum_xx += (x * x)
  end

  # Linear Regression Calculation (Least Squares)
  # y = mx + b
  # m (slope) = (n*sum_xy - sum_x*sum_y) / (n*sum_xx - sum_x*sum_x)
  # b (intercept) = (sum_y - m*sum_x) / n

  denominator = (n * sum_xx) - (sum_x * sum_x)
  
  if denominator == 0
    event.respond "Cannot predict: Quake data is invalid (infinite slope)."
    return
  end

  slope = (n * sum_xy - sum_x * sum_y).to_f / denominator
  intercept = (sum_y - slope * sum_x) / n

  # Predict next quake (x = n)
  next_x = n
  predicted_timestamp = slope * next_x + intercept
  predicted_time = Time.at(predicted_timestamp)
  
  # Calculate average interval for display
  interval_duration = slope # The slope is effectively the average interval in seconds

  output = []
  output << "**Quake Prediction (Linear Regression)**"
  output << "Based on #{n} recorded quakes."
  output << "Predicted Next Quake: **#{predicted_time.in_time_zone(ENV["TZ"]).strftime("%A, %B %d at %I:%M:%S %p %Z")}**"
  output << "Estimated Interval: #{ChronicDuration.output(interval_duration, format: :long)}"
  
  event.respond output.join("\n")
end

def list_recent_quakes(event)
  quakes = Earthquake.order(Sequel.desc(:timestamp)).limit(20).all

  if quakes.empty?
    event.respond "No quakes recorded yet."
    return
  end

  output = []
  output << "**Recent Quakes (Last #{quakes.count})**"
  output << "```"
  quakes.each do |quake|
    time = Time.at(quake.timestamp)
    output << time.in_time_zone(ENV["TZ"]).strftime("%Y-%m-%d %I:%M:%S %p %Z")
  end
  output << "```"

  event.respond output.join("\n")
end

def predict_quake_probability(event)
  quakes = Earthquake.order(:timestamp).all

  if quakes.count < 2
    event.respond "Not enough data to calculate probabilities. Need at least 2 recorded quakes."
    return
  end

  timestamps = quakes.map(&:timestamp)
  last_quake_time = timestamps.last
  time_since_last = Time.now.to_f - last_quake_time
  
  intervals = []
  timestamps.each_cons(2) do |t1, t2|
    intervals << (t2 - t1)
  end
  
  # Filter intervals that are longer than current elapsed time
  valid_intervals = intervals.select { |i| i > time_since_last }
  
  # Total historical instances where we waited at least this long
  total_valid = valid_intervals.count
  
  if total_valid == 0
    prob_1h = 100.0
    prob_24h = 100.0
    note = "(Overdue: Current wait time of #{ChronicDuration.output(time_since_last.to_i, format: :long)} exceeds all historical intervals)"
  else
    # Count how many of these valid intervals happened within the next hour/24h relative to current wait
    count_1h = valid_intervals.count { |i| i <= time_since_last + 3600 }
    count_24h = valid_intervals.count { |i| i <= time_since_last + 86400 }
    
    prob_1h = (count_1h.to_f / total_valid) * 100
    prob_24h = (count_24h.to_f / total_valid) * 100
    note = ""
  end

  output = []
  output << "**Quake Probability Analysis**"
  output << "Based on #{intervals.count} historical intervals."
  output << "Time since last quake: #{ChronicDuration.output(time_since_last.to_i, format: :long) || '0s'}"
  output << ""
  output << "Chance within next hour: **#{prob_1h.round(1)}%**"
  output << "Chance within next 24 hours: **#{prob_24h.round(1)}%** #{note}"

  event.respond output.join("\n")
end

def predict_quake_probability2(event)
  now = Time.now
  timestamps = Earthquake.order(:timestamp).pluck(:timestamp).map(&:to_f)

  if timestamps.length < 2
    event.respond "Not enough data to calculate probabilities. Need at least 2 recorded quakes."
    return
  end

  last_quake_time = timestamps.last
  time_since_last = now.to_f - last_quake_time

  intervals = timestamps.each_cons(2).map { |t1, t2| (t2 - t1).to_f }.select { |d| d > 0 }

  if intervals.empty?
    event.respond "Not enough valid intervals to calculate probabilities."
    return
  end

  delta_1h = 3600.0
  delta_today = [now.end_of_day.to_f - now.to_f, 0.0].max

  # Empirical conditional probability: P(s < I <= s+Δ | I > s)
  survival = intervals.count { |i| i > time_since_last }

  if survival == 0
    max_gap = intervals.max
    note = "Out of sample: waited #{ChronicDuration.output(time_since_last.to_i)}; historical max gap is #{ChronicDuration.output(max_gap.to_i)}."
    prob_1h = nil
    prob_today = nil
  else
    count_1h = intervals.count { |i| i > time_since_last && i <= time_since_last + delta_1h }
    count_today = intervals.count { |i| i > time_since_last && i <= time_since_last + delta_today }

    prob_1h = 100.0 * count_1h / survival
    prob_today = 100.0 * count_today / survival
    note = ""
  end

  output = []
  output << "**Quake Probability Analysis (Empirical Renewal Model)**"
  output << "Based on #{intervals.length} historical intervals."
  output << "Time since last quake: #{ChronicDuration.output(time_since_last.to_i, format: :long) || '0s'}"
  output << ""

  if prob_1h.nil?
    output << "Chance within next hour: **N/A**"
    output << "Chance by end of today: **N/A**"
    output << note
  else
    output << "Chance within next hour: **#{prob_1h.round(1)}%**"
    output << "Chance by end of today: **#{prob_today.round(1)}%** #{note}"
  end

  event.respond output.join("\n")
end
