require 'discordrb/webhooks'

def build_timer_message_three(timers: nil)
  any_in_window = false
  mobs_in_window = []
  upcoming_window = []
  future_window = []
  number_of_blocks = 14
  max_fields_per_embed = 25

  timers ||= Timer.all
  timers = timers.sort_by {|timer| next_spawn_time_start(timer.name, timer: timer) || Chronic.parse("100 years from now") }
  if TIMER_MESSAGE_THREE_ORDER == "reverse"
    timers = timers.reverse
  end

  timers.each do |timer|
    window_start = ""
    vague_window_start = ""
    starts_at = ""
    ends_at = ""
    window_end = ""
    no_window_end = false
    last_tod = ""

    if timer.last_tod
      tod = Time.at(timer.last_tod)
      last_tod = display_time_ago(tod)
      starts_at = next_spawn_time_start(timer.name, timer: timer)
      ends_at = next_spawn_time_end(timer.name, timer: timer)
      window_start = display_time_distance(starts_at, true, words_connector: " ", last_word_connector: " ", two_words_connector: " ")
      vague_window_start = display_time_distance(starts_at, false, words_connector: " ", last_word_connector: " ", two_words_connector: " ", highest_measures: 2)

      if timer.window_end || timer.variance
        window_end = display_time_distance(ends_at, true, words_connector: " ", last_word_connector: " ", two_words_connector: " ")
      else
        no_window_end = true
        window_end = window_start
      end
    else
      last_tod = false
    end

    begin
      timer_name = timer.name
      if timer.skip_count.to_i > 0
        timer_name = timer_name + ("*" * timer.skip_count.to_i)
      end

      if !last_tod
        any_need_tod = true
      elsif in_window(timer.name, timer: timer)
        line = ""

        if ends_at > Time.now
          perc = (((Time.now - starts_at) / (ends_at - starts_at)))
          num = (number_of_blocks * perc).round(0)

          if USE_DISCORD_TIMESTAMPS
            out = "Window ends <t:#{ends_at.to_time.utc.to_i}:R>\n"
          else
            out = "Remaining: #{display_time_distance(ends_at, true, words_connector: " ", last_word_connector: " ", two_words_connector: " ")}\n"
          end

          number_of_blocks.times do |i|
            if i >= num
              out += "⬜"
            else
              out += "🟩"
            end
          end
          any_in_window = true

          mobs_in_window << {
            message: Discordrb::Webhooks::EmbedField.new(
              name: "#{timer.name} (*#{timer.display_window(format: :long)}*)",
              value: out
            ),
            percent: perc
          }
        else
          #any_ended_recently = true
          #line += "#{truncated_timer_name}".ljust(COLUMN_1, ' ')
          #line += "#{window_end} ago".ljust(COLUMN_2, ' ')
          #line += "".ljust(COLUMN_3, ' ')
          #ine += ends_at.in_time_zone("Eastern Time (US & Canada)").strftime("%m/%d %I:%M:%S %p %Z").ljust(COLUMN_4, ' ')
          #ended_recently_message << "`#{line}`"
        end
      elsif starts_at <= Time.now + (24 * 60 * 60)
        #line = ""
        #any_mobs = true
        #line += "#{truncated_timer_name}".ljust(COLUMN_1, ' ')
        #line += "#{window_start}".ljust(COLUMN_2, ' ')
        #if !no_window_end && timer.display_window
        #  line += timer.display_window.ljust(COLUMN_3, ' ')
        #else
        #  line += "".ljust(COLUMN_3, ' ')
        #end
        #line += starts_at.in_time_zone("Eastern Time (US & Canada)").strftime("%m/%d %I:%M:%S %p %Z").ljust(COLUMN_4, ' ')
        #upcoming_message << "`#{line}`"
        if USE_DISCORD_TIMESTAMPS
          upcoming_window << Discordrb::Webhooks::EmbedField.new(
            name: "#{timer.name}"  + (timer.has_window? ? " (*#{timer.display_window(format: :long)}*)" : ""),
            value: "Opens <t:#{starts_at.to_time.utc.to_i}:R>"
          )
        else
          upcoming_window << Discordrb::Webhooks::EmbedField.new(
            name: "#{timer.name}"  + (timer.has_window? ? " (*#{timer.display_window(format: :long)}*)" : ""),
            value: "Opens in: #{window_start}"
          )
        end
      else
        if CONDENSE_FUTURE_WINDOW
          future_window << "**#{timer.name}** (<t:#{starts_at.to_time.utc.to_i}:R>)"
        else
          if USE_DISCORD_TIMESTAMPS
            future_window << "**#{timer.name}** #{(timer.has_window? ? "(*#{timer.display_window(format: :long)})* " : "")}- <t:#{starts_at.to_time.utc.to_i}:R>"
          else
            future_window << "**#{timer.name}** #{(timer.has_window? ? "(*#{timer.display_window(format: :long)})* " : "")}- #{vague_window_start}"
          end
        end
      end
    rescue => ex
      puts ex
      puts ex.backtrace
    end
  end

  mobs_in_window = mobs_in_window.sort_by {|m| -(m[:percent].to_f) }

  client = Discordrb::Webhooks::Client.new(url: TIMER_CHANNEL_WEBHOOK_URL)
  builder = Discordrb::Webhooks::Builder.new
  builder.content = ""

  embeds = []
  embeds << Proc.new {|embed|
    embed.color = any_in_window ? 15105570 : 3066993
    embed.title = any_in_window ? "Mobs In Window" : "Nothing Currently in Window"
    embed.fields = mobs_in_window.take(max_fields_per_embed).map {|m| m[:message] }
    embed.footer =  Discordrb::Webhooks::EmbedFooter.new(text: any_in_window ? "These are currently in window! Be prepared! • Today at #{Time.now.strftime("%I:%M:%S %p")}" : "There is currently nothing in window! • Today at #{Time.now.strftime("%I:%M:%S %p")}")
  }

  embeds << Proc.new {|embed|
    embed.color = 3447003
    embed.title = "Mobs Entering Window In The Next 24 Hours"
    embed.fields = upcoming_window.take(max_fields_per_embed)
  }

  if SHOW_FUTURE_WINDOW && future_window.size > 0
    embeds << Proc.new {|embed|
      embed.title = "Future Windows"
      if CONDENSE_FUTURE_WINDOW
        embed.description = future_window.join(", ")
      else
        embed.description = future_window.join("\n")
      end
    }
  end

  # --- Earthquake Prediction Embed ---
  timestamps = Earthquake.order(:timestamp).pluck(:timestamp).map(&:to_f)
  if timestamps.count >= 3
    begin
      tz = ENV["TZ"] || "America/New_York"

      cached_json = Setting.find_by_key("quake_prediction_cache")
      cache = cached_json ? JSON.parse(cached_json) : nil

      result = nil
      if cache && cache["updated_at"] && (Time.now.to_i - cache["updated_at"] < 3600)
        r = cache["result"]
        result = {
          pred_time: Time.at(r["pred_time"]).in_time_zone(tz),
          pred_day_probability: r["pred_day_probability"],
          today_probability: r["today_probability"],
          pred_interval_50: {
            start: Time.at(r["pred_interval_50"]["start"]).in_time_zone(tz),
            end: Time.at(r["pred_interval_50"]["end"]).in_time_zone(tz)
          },
          pred_interval_90: {
            start: Time.at(r["pred_interval_90"]["start"]).in_time_zone(tz),
            end: Time.at(r["pred_interval_90"]["end"]).in_time_zone(tz)
          },
          mae_seconds: r["mae_seconds"],
          rmse_seconds: r["rmse_seconds"]
        }
      else
        result = bootstrap_quake_probabilities(timestamps, tz: tz)

        cache_payload = {
          updated_at: Time.now.to_i,
          result: {
            pred_time: result[:pred_time].to_f,
            pred_day_probability: result[:pred_day_probability],
            today_probability: result[:today_probability],
            pred_interval_50: {
              start: result[:pred_interval_50][:start].to_f,
              end: result[:pred_interval_50][:end].to_f
            },
            pred_interval_90: {
              start: result[:pred_interval_90][:start].to_f,
              end: result[:pred_interval_90][:end].to_f
            },
            mae_seconds: result[:mae_seconds],
            rmse_seconds: result[:rmse_seconds]
          }
        }
        Setting.save_by_key("quake_prediction_cache", cache_payload.to_json)
      end
      
      pred_time = result[:pred_time]
      prob_pred_day = result[:pred_day_probability]
      prob_today = result[:today_probability]
      interval_50 = result[:pred_interval_50]
      interval_90 = result[:pred_interval_90]
      mae = result[:mae_seconds]
      rmse = result[:rmse_seconds]

      embeds << Proc.new {|embed|
        embed.title = "Quake Prediction (Bootstrap)"
        embed.color = 9807270 # A distinct color (e.g., brownish/red)
        
        description = []
        description << "Point Prediction: **#{pred_time.strftime("%A, %B %d at %I:%M:%S %p %Z")}**"
        description << "Prob Today: **#{(prob_today * 100).round(1)}%**"
        description << "Prob Predicted Day: **#{(prob_pred_day * 100).round(1)}%**"
        description << "50% PI: #{interval_50[:start].strftime("%b %d %I:%M %p")} – #{interval_50[:end].strftime("%b %d %I:%M %p")}"
        description << "90% PI: #{interval_90[:start].strftime("%b %d %I:%M %p")} – #{interval_90[:end].strftime("%b %d %I:%M %p")}"
        
        embed.description = description.join("\n")
      }
    rescue => ex
      puts "Error generating quake embed: #{ex.message}"
    end
  end

  if TIMER_MESSAGE_THREE_ORDER == "reverse"
    embeds = embeds.reverse
  end

  embeds.each do |embed|
    builder.add_embed(&embed)
  end

  webhook_message_id = Setting.find_by_key("webhook_message_id")

  # Delete and create
  if false
    if webhook_message_id
      begin
        channel = BOT.channel(TIMER_CHANNEL_ID)
        channel.delete_message(webhook_message_id)
      rescue => ex
      end
    end

    result = client.execute(builder, true)
    response = JSON.parse(result.body)
    webhook_message_id = response["id"]
    Setting.save_by_key("webhook_message_id", webhook_message_id)

  # Create or update
  else
    if webhook_message_id == nil
      result = client.execute(builder, true)
      response = JSON.parse(result.body)
      webhook_message_id = response["id"]
      Setting.save_by_key("webhook_message_id", webhook_message_id)
    else
      begin
        client.edit_message(webhook_message_id, builder: builder)
      rescue => ex
        puts ex
        if ex.message =~ /404 Not Found/
          result = client.execute(builder, true)
          response = JSON.parse(result.body)
          webhook_message_id = response["id"]
          Setting.save_by_key("webhook_message_id", webhook_message_id)
        end
      end
    end
  end
end
