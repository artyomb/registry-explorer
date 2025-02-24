require_relative 'common_utils'
class TimeMeasurer
  @@current_measurer = nil
  @@total_measurers_count = 0
  @order = nil
  @times_dict = nil

  def times_dict
    @times_dict
  end

  def order
    @order
  end

  def self.start_measurement
    @@current_measurer = TimeMeasurer.new
  end

  def self.measure(key, one_simultaneous = true, &block)
    @@current_measurer.send(:add_measurement_key, key, one_simultaneous)
    @@current_measurer.send(:measure, key, &block)
  end

  def self.current_measurer
    @@current_measurer
  end

  def self.log_measurers
    @@current_measurer.send(:log_measurers)
  end

  private

  def add_measurement_key(key, one_simultaneous = true)
    # one_simultaneous is used to avoid measuring the same key multiple times
    @times_dict.key?(key) ? nil : @times_dict[key] = { time_ranges: Set.new, one_simultaneous: one_simultaneous }
    # @times_dict.key?(key) ? nil : @times_dict[key] = 0
  end

  def initialize()
    @times_dict = {}
    TimeMeasurer.class_variable_set(:@@total_measurers_count, TimeMeasurer.class_variable_get(:@@total_measurers_count) + 1)
    @order = TimeMeasurer.class_variable_get(:@@total_measurers_count)
  end

  def measure(key, &block)
    start_time = Time.now
    result = yield
    end_time = Time.now
    @times_dict[key][:time_ranges].add({ start: start_time, end: end_time })
    # @times_dict[key] += end_time - start_time
    result
  end

  def log_measurers
    puts "Measurers in #{@order} set:"
    puts "-" * 80
    puts "| %-60s | %-15s |" % ["Operation", "Time (ms)"]
    puts "-" * 80
    @times_dict.each do |key, value|
      puts "| %-60s | %15.2f |" % [key, calculate_duration(key) * 1000]
    end
    puts "-" * 80
  end

  def calculate_duration(key)
    if self.times_dict[key][:one_simultaneous]
      calculate_unique_duration(@times_dict[key][:time_ranges])
    else
      @times_dict[key][:time_ranges].sum do |range|
        range[:end_time] - range[:start_time]
      end
    end
    # @times_dict[key]
  end
end