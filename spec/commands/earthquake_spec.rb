require "spec_helper"

def update_timers_channel
  nil
end

describe "EarthquakeCommand" do
  before do
    allow(BOT).to receive(:send_message)
  end

  it "should record earthquake" do
    user = double("User")
    
    channel = double("Channel")
    expect(channel).to receive(:id) { COMMAND_CHANNEL_ID }

    message = double("Message")

    event = double("Event")
    expect(event).to receive(:channel).at_least(:once) { channel }
    allow(event).to receive(:user) { user }
    allow(event).to receive(:message) { message }
    expect(event).to receive(:respond).with(/Quake has been registered!/)

    expect {
      command_quake(event, ["now"])
    }.to change { Earthquake.count }.by(1)
  end

  it "should record earthquake with specific time" do
    user = double("User")
    
    channel = double("Channel")
    expect(channel).to receive(:id) { COMMAND_CHANNEL_ID }

    message = double("Message")

    event = double("Event")
    expect(event).to receive(:channel).at_least(:once) { channel }
    allow(event).to receive(:user) { user }
    allow(event).to receive(:message) { message }
    expect(event).to receive(:respond).with(/Quake has been registered!/)

    time_string = "1 hour ago"
    
    expect {
      command_quake(event, [time_string])
    }.to change { Earthquake.count }.by(1)
    
    # Check timestamp roughly
    last_quake = Earthquake.last
    expect(last_quake.timestamp).to be_within(5).of((Time.now - 3600).to_f)
  end

  it "should fail to predict with insufficient data" do
    Earthquake.dataset.delete # Ensure clean state
    Earthquake.create(timestamp: Time.now.to_f, created_at: Time.now)
    
    user = double("User")
    channel = double("Channel")
    expect(channel).to receive(:id) { COMMAND_CHANNEL_ID }

    message = double("Message")
    event = double("Event")
    expect(event).to receive(:channel).at_least(:once) { channel }
    allow(event).to receive(:user) { user }
    allow(event).to receive(:message) { message }
    
    expect(event).to receive(:respond).with("Not enough data to predict the next quake. Need at least 2 recorded quakes.")

    command_quake(event, ["predict"])
  end

  it "should predict next quake with linear regression" do
    Earthquake.dataset.delete # Ensure clean state
    
    # Create 3 quakes spaced 1 hour apart
    base_time = Time.now - 10000
    Earthquake.create(timestamp: base_time.to_f, created_at: Time.now)
    Earthquake.create(timestamp: (base_time + 3600).to_f, created_at: Time.now)
    Earthquake.create(timestamp: (base_time + 7200).to_f, created_at: Time.now)

    user = double("User")
    channel = double("Channel")
    expect(channel).to receive(:id) { COMMAND_CHANNEL_ID }

    message = double("Message")
    event = double("Event")
    expect(event).to receive(:channel).at_least(:once) { channel }
    allow(event).to receive(:user) { user }
    allow(event).to receive(:message) { message }
    
    # Expected next quake is +3600 from the last one (total 3 * 3600 from base)
    expected_time = base_time + (3 * 3600)
    
    expect(event).to receive(:respond) do |response|
      expect(response).to include("Quake Prediction (Linear Regression)")
      expect(response).to include("Predicted Next Quake")
      expect(response).to include("Estimated Interval: 1 hr")
    end

    command_quake(event, ["predict"])
  end

  it "should list recent quakes" do
    Earthquake.dataset.delete # Ensure clean state
    
    # Create a quake
    Earthquake.create(timestamp: Time.now.to_f, created_at: Time.now)

    user = double("User")
    channel = double("Channel")
    expect(channel).to receive(:id) { COMMAND_CHANNEL_ID }

    message = double("Message")
    event = double("Event")
    expect(event).to receive(:channel).at_least(:once) { channel }
    allow(event).to receive(:user) { user }
    allow(event).to receive(:message) { message }
    
    expect(event).to receive(:respond) do |response|
      expect(response).to include("Recent Quakes")
      expect(response).to include(Time.now.in_time_zone(ENV["TZ"]).strftime("%Y-%m-%d"))
    end

    command_quake(event, ["list"])
  end
end
