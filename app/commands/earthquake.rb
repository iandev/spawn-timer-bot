BOT.command(:earthquake) do |event, *args|
  command_quake(event, *args)
end

BOT.command(:quake) do |event, *args|
  command_quake(event, *args)
end

def command_quake(event, *args)
  everyone_alert = USE_EVERYONE_ALERT ? "@everyone " : ""

  return if event.channel.id != COMMAND_CHANNEL_ID

  if args.first.to_s.downcase == "predict2"
    predict_next_quake(event)
    return
  end

  if args.first.to_s.downcase == "chance"
    predict_quake_probability2(event)
    return
  end

  if args.first.to_s.downcase == "predict"
    predict_quake_bootstrap(event)
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
    output << "!quake predict2"
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

def predict_quake_bootstrap(event)
  timestamps = Earthquake.order(:timestamp).pluck(:timestamp).map(&:to_f)

  if timestamps.count < 3
    event.respond "Not enough data for bootstrap prediction. Need at least 3 recorded quakes."
    return
  end

  # Default to Eastern Time if ENV["TZ"] is not set
  tz = ENV["TZ"] || "America/New_York"

  begin
    result = bootstrap_quake_probabilities(timestamps, tz: tz)
  rescue => e
    event.respond "Error calculating bootstrap probabilities: #{e.message}"
    return
  end

  pred_time = result[:pred_time]
  prob_pred_day = result[:pred_day_probability]
  prob_today = result[:today_probability]
  interval_50 = result[:pred_interval_50]
  interval_90 = result[:pred_interval_90]
  mae = result[:mae_seconds]
  rmse = result[:rmse_seconds]

  output = []
  output << "**Quake Prediction (Bootstrap)**"
  output << "Based on #{timestamps.count} recorded quakes (10,000 simulations)."
  output << ""
  output << "Point Prediction: **#{pred_time.strftime("%A, %B %d at %I:%M:%S %p %Z")}**"
  output << ""
  output << "**Probabilities:**"
  output << "• On Predicted Day (#{pred_time.strftime("%Y-%m-%d")}): **#{(prob_pred_day * 100).round(1)}%**"
  output << "• Today: **#{(prob_today * 100).round(1)}%**"
  output << ""
  output << "**Prediction Intervals:**"
  output << "• 50% PI: #{interval_50[:start].strftime("%b %d %I:%M %p")} – #{interval_50[:end].strftime("%b %d %I:%M %p")}"
  output << "• 90% PI: #{interval_90[:start].strftime("%b %d %I:%M %p")} – #{interval_90[:end].strftime("%b %d %I:%M %p")}"
  output << ""
  output << "Stats: MAE=#{(mae / 86_400.0).round(2)}d, RMSE=#{(rmse / 86_400.0).round(2)}d"

  event.respond output.join("\n")
end

def bootstrap_quake_probabilities(timestamps,
                                 tz: "America/New_York",
                                 bootstrap_samples: 10_000,
                                 seed: nil)
  zone = Time.find_zone!(tz)
  now = Time.current.in_time_zone(zone)

  ys = timestamps.map(&:to_f)
  n = ys.length
  raise ArgumentError, "Need at least 3 events (got #{n})." if n < 3

  xs = (0...n).map(&:to_f)
  x0 = n.to_f

  # --- helpers ---
  fit = lambda do |x_arr, y_arr|
    nn = y_arr.length.to_f
    sum_x  = x_arr.sum
    sum_y  = y_arr.sum
    sum_xy = x_arr.zip(y_arr).sum { |x, y| x * y }
    sum_xx = x_arr.sum { |x| x * x }

    denom = (nn * sum_xx) - (sum_x * sum_x)
    raise "Regression denominator ~0 (degenerate x values)" if denom.abs < 1e-12

    m = ((nn * sum_xy) - (sum_x * sum_y)) / denom
    b = (sum_y - m * sum_x) / nn
    [m, b]
  end

  predict = ->(m, b, x) { (m * x) + b }

  quantile = lambda do |sorted_arr, p|
    return nil if sorted_arr.empty?
    p = [[p, 0.0].max, 1.0].min
    i = p * (sorted_arr.length - 1)
    lo = i.floor
    hi = i.ceil
    return sorted_arr[lo] if lo == hi
    w = i - lo
    sorted_arr[lo] * (1.0 - w) + sorted_arr[hi] * w
  end

  day_window = lambda do |date|
    start = zone.local(date.year, date.month, date.day)
    [start.to_f, (start + 1.day).to_f]
  end

  rng = seed ? Random.new(seed) : Random.new
  bsz = bootstrap_samples.to_i
  raise ArgumentError, "bootstrap_samples must be >= 1000" if bsz < 1000

  # --- original fit ---
  m, b = fit.call(xs, ys)
  yhat = xs.map { |x| predict.call(m, b, x) }
  residuals = ys.zip(yhat).map { |y, yh| y - yh }

  mae  = residuals.sum { |e| e.abs } / n.to_f
  rmse = Math.sqrt(residuals.sum { |e| e * e } / n.to_f)

  yhat0 = predict.call(m, b, x0)
  pred_time = Time.at(yhat0).in_time_zone(zone)
  pred_date = pred_time.to_date

  pred_day_start, pred_day_end = day_window.call(pred_date)
  today_start, today_end       = day_window.call(now.to_date)

  # Center residuals for residual bootstrap
  mean_resid = residuals.sum / n.to_f
  centered_resids = residuals.map { |e| e - mean_resid }

  hits_pred_day = 0
  hits_today = 0
  boot_pred_times = Array.new(bsz)

  bsz.times do |j|
    boot_resids = Array.new(n) { centered_resids[rng.rand(n)] }
    y_boot = yhat.zip(boot_resids).map { |yh, e| yh + e }

    m_star, b_star = fit.call(xs, y_boot)
    y0_star = predict.call(m_star, b_star, x0)

    boot_pred_times[j] = y0_star

    hits_pred_day += 1 if (y0_star >= pred_day_start && y0_star < pred_day_end)
    hits_today    += 1 if (y0_star >= today_start    && y0_star < today_end)
  end

  boot_pred_times.sort!
  q05 = quantile.call(boot_pred_times, 0.05)
  q25 = quantile.call(boot_pred_times, 0.25)
  q75 = quantile.call(boot_pred_times, 0.75)
  q95 = quantile.call(boot_pred_times, 0.95)

  interval_50 = { start: Time.at(q25).in_time_zone(zone), end: Time.at(q75).in_time_zone(zone) }
  interval_90 = { start: Time.at(q05).in_time_zone(zone), end: Time.at(q95).in_time_zone(zone) }

  prob_pred_day = hits_pred_day.to_f / bsz
  prob_today    = hits_today.to_f / bsz

  description = [
    "Bootstrap (#{bsz} sims) residual-bootstrap+refit on linear regression (index → timestamp).",
    "Point prediction: #{pred_time.strftime("%A, %B %d, %Y %I:%M:%S %p %Z")}.",
    "P(on predicted day #{pred_date})=#{(prob_pred_day * 100).round(1)}%.",
    "P(today #{now.to_date})=#{(prob_today * 100).round(1)}%.",
    "50% PI=[#{interval_50[:start].strftime("%b %d %I:%M %p")} – #{interval_50[:end].strftime("%b %d %I:%M %p")}],",
    "90% PI=[#{interval_90[:start].strftime("%b %d %I:%M %p")} – #{interval_90[:end].strftime("%b %d %I:%M %p")}],",
    "MAE=#{(mae / 86_400.0).round(2)}d RMSE=#{(rmse / 86_400.0).round(2)}d."
  ].join(" ")

  {
    slope_seconds_per_event: m,
    mae_seconds: mae,
    rmse_seconds: rmse,
    pred_time: pred_time,
    pred_day_probability: prob_pred_day,
    today_probability: prob_today,
    pred_interval_50: interval_50,
    pred_interval_90: interval_90,
    description: description
  }
end
