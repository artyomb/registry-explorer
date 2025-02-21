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

  def self.measure(key, &block)
    @@current_measurer.send(:add_measurement_key, key)
    @@current_measurer.send(:measure, key, &block)
  end

  def self.current_measurer
    @@current_measurer
  end

  def self.log_measurers
    @@current_measurer.send(:log_measurers)
  end

  private

  def add_measurement_key(key)
    @times_dict.key?(key) ? nil : @times_dict[key] = 0
  end

  def initialize()
    @times_dict = {}
    TimeMeasurer.class_variable_set(:@@total_measurers_count, TimeMeasurer.class_variable_get(:@@total_measurers_count) + 1)
    @order = TimeMeasurer.class_variable_get(:@@total_measurers_count)
  end

  def measure(key, &block)
    start_time = Time.now
    result = yield
    @times_dict[key] += Time.now - start_time
    result
  end

  def log_measurers
    puts "Measurers in #{@order} set:"
    @times_dict.each do |key, value|
      puts "#{key} - #{value}"
    end
  end
end