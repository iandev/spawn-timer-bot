require 'spec_helper'

RSpec.describe "Earthquake Prediction" do
  let(:event) { double('event', channel: double('channel', id: COMMAND_CHANNEL_ID)) }

  before do
    allow(event).to receive(:respond)
    Earthquake.dataset.destroy
  end

  describe "predict_quake_probability" do
    it "responds with error if not enough data" do
      Earthquake.create(timestamp: Time.now.to_f)
      
      predict_quake_probability(event)
      expect(event).to have_received(:respond).with("Not enough data to calculate probabilities. Need at least 2 recorded quakes.")
    end

    it "calculates probabilities correctly" do
      # Setup scenario:
      # Quakes happened at: T-100h, T-50h, T-20h
      # Intervals: 50h, 30h
      # Current wait: 20h
      
      now = Time.now
      t1 = now - (100 * 3600)
      t2 = now - (50 * 3600)
      t3 = now - (20 * 3600)
      
      Earthquake.create(timestamp: t1.to_f)
      Earthquake.create(timestamp: t2.to_f)
      Earthquake.create(timestamp: t3.to_f)
      
      # Intervals:
      # t2 - t1 = 50 hours
      # t3 - t2 = 30 hours
      
      # Time since last (t3) = 20 hours
      
      # Logic trace:
      # valid_intervals ( > 20h): 50h, 30h. Count = 2.
      
      # Next hour check ( <= 20h + 1h = 21h):
      # 50h <= 21h (False)
      # 30h <= 21h (False)
      # count_1h = 0
      # prob_1h = 0%
      
      # Next 24h check ( <= 20h + 24h = 44h):
      # 50h <= 44h (False)
      # 30h <= 44h (True)
      # count_24h = 1
      # prob_24h = 50%
      
      predict_quake_probability(event)
      
      expect(event).to have_received(:respond) do |msg|
        expect(msg).to include("Chance within next hour: **0.0%**")
        expect(msg).to include("Chance within next 24 hours: **50.0%**")
      end
    end

    it "handles overdue scenario" do
      now = Time.now
      t1 = now - (100 * 3600)
      t2 = now - (90 * 3600)
      
      Earthquake.create(timestamp: t1.to_f)
      Earthquake.create(timestamp: t2.to_f)
      
      # Interval: 10h
      # Time since last: 90h
      
      # Valid intervals > 90h: None.
      
      predict_quake_probability(event)
      
      expect(event).to have_received(:respond) do |msg|
        expect(msg).to include("Chance within next hour: **100.0%**")
        expect(msg).to include("Chance within next 24 hours: **100.0%**")
        expect(msg).to include("Overdue")
      end
    end
  end
end
