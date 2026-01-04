require "spec_helper"

RSpec.describe "MessageThree" do
  before do
    # Create 3 earthquakes
    3.times do |i|
      Earthquake.create(timestamp: Time.now - i * 86400)
    end
    
    # Mock Discord client
    client_double = double("Discordrb::Webhooks::Client")
    allow(Discordrb::Webhooks::Client).to receive(:new).and_return(client_double)
    allow(client_double).to receive(:execute).and_return(double(body: '{"id": "123"}'))
    allow(client_double).to receive(:edit_message)
    
    # Clear settings
    Setting.delete_by_key("quake_prediction_cache")
    Setting.delete_by_key("webhook_message_id")
  end

  it "caches bootstrap_quake_probabilities result" do
    # Spy on the method
    # Note: Since methods are top-level, 'self' should respond to them in this context
    allow(self).to receive(:bootstrap_quake_probabilities).and_call_original
    
    # 1. First call - should run calculation
    build_timer_message_three
    expect(self).to have_received(:bootstrap_quake_probabilities).once
    
    # Verify cache created
    cache = Setting.find_by_key("quake_prediction_cache")
    expect(cache).not_to be_nil
    
    # 2. Second call (immediate) - should use cache
    build_timer_message_three
    expect(self).to have_received(:bootstrap_quake_probabilities).once # Still once
    
    # 3. Third call after time travel (expired cache) - should run calculation
    Timecop.travel(Time.now + 3601) do
      build_timer_message_three
      expect(self).to have_received(:bootstrap_quake_probabilities).twice
    end
  end
end
