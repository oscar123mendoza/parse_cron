require 'set'
require 'date'

# Parses cron expressions and computes the next occurence of the "job"
#
class CronParser
  # internal "mutable" time representation
  class InternalTime
    attr_accessor :year, :month, :day, :hour, :min, :sec
    attr_accessor :time_source

    def initialize(time = Time.now, time_source = Time)
      @year = time.year
      @month = time.month
      @day = time.day
      @hour = time.hour
      @min = time.min
      @sec = time.sec

      @time_source = time_source
    end

    def to_time
      time_source.local(@year, @month, @day, @hour, @min, @sec)
    end

    def inspect
      [year, month, day, hour, min, sec].inspect
    end
  end

  SYMBOLS = {
     "jan" => "1",
     "feb" => "2",
     "mar" => "3",
     "apr" => "4",
     "may" => "5",
     "jun" => "6",
     "jul" => "7",
     "aug" => "8",
     "sep" => "9",
     "oct" => "10",
     "nov" => "11",
     "dec" => "12",

     "sun" => "0",
     "mon" => "1",
     "tue" => "2",
     "wed" => "3",
     "thu" => "4",
     "fri" => "5",
     "sat" => "6"
  }

  def initialize(source,time_source = Time)
    @source = interpret_vixieisms(source)
    @time_source = time_source
    validate_source
  end

  def interpret_vixieisms(spec)
    case spec
    when '@reboot'
      raise ArgumentError, "Can't predict last/next run of @reboot"
    when '@yearly', '@annually'
      '0 0 1 1 *'
    when '@monthly'
      '0 0 1 * *'
    when '@weekly'
      '0 0 * * 0'
    when '@daily', '@midnight'
      '0 0 * * *'
    when '@hourly'
      '0 * * * *'
    when '@minutely'
      '* * * * *'
    else
      spec
    end
  end


  # returns the next occurence after the given date
  def next(now = @time_source.now, num = 1)
    t = InternalTime.new(now, @time_source)

    unless time_specs[:year][0].include?(t.year)
      nudge_year(t)
      t.month = 0
    end

    unless time_specs[:month][0].include?(t.month)
      nudge_month(t)
      t.day = 0
    end

    unless interpolate_weekdays(t.year, t.month)[0].include?(t.day)
      nudge_date(t)
      t.hour = -1
    end

    unless time_specs[:hour][0].include?(t.hour)
      nudge_hour(t)
      t.min = -1
    end

    unless time_specs[:minute][0].include?(t.min)
      nudge_minute(t)
      t.sec = -1
    end

    # always nudge the second
    nudge_second(t)
    t = t.to_time
    if num > 1
      recursive_calculate(:next,t,num)
    else
      t
    end
  end

  # returns the last occurence before the given date
  def last(now = @time_source.now, num=1)
    t = InternalTime.new(now,@time_source)

    unless time_specs[:year][0].include?(t.year)
      nudge_year(t, :last)
      t.month = 13
    end

    unless time_specs[:month][0].include?(t.month)
      nudge_month(t, :last)
      t.day = 32
    end

    if t.day == 32 || !interpolate_weekdays(t.year, t.month)[0].include?(t.day)
      nudge_date(t, :last)
      t.hour = 24
    end

    unless time_specs[:hour][0].include?(t.hour)
      nudge_hour(t, :last)
      t.min = 60
    end

    unless time_specs[:minute][0].include?(t.min)
      nudge_minute(t, :last)
      t.sec = 60
    end

    # always nudge the second
    nudge_second(t, :last)
    t = t.to_time
    if num > 1
      recursive_calculate(:last,t,num)
    else
      t
    end
  end


  SUBELEMENT_REGEX = %r{^(\d+)(-(\d+)(/(\d+))?)?$}
  def parse_element(elem, allowed_range)
    values = elem.split(',').map do |subel|
      if subel =~ /^\*/
        step = subel.length > 1 ? subel[2..-1].to_i : 1
        stepped_range(allowed_range, step)
      elsif subel =~ /^\?$/ && (allowed_range == (1..31) || allowed_range == (0..6))
        step = subel.length > 1 ? subel[2..-1].to_i : 1
        stepped_range(allowed_range, step)
      else
        if SUBELEMENT_REGEX === subel
          if $5 # with range
            stepped_range($1.to_i..$3.to_i, $5.to_i)
          elsif $3 # range without step
            stepped_range($1.to_i..$3.to_i, 1)
          else # just a numeric
            [$1.to_i]
          end
        else
          raise ArgumentError, "Bad Vixie-style specification #{subel}"
        end
      end
    end.flatten.sort

    [Set.new(values), values, elem]
  end


  protected

  def recursive_calculate(meth,time,num)
    array = [time]
    num.-(1).times do |num|
      array << self.send(meth, array.last)
    end
    array
  end

  # returns a list of days which do both match time_spec[:dom] or time_spec[:dow]
  def interpolate_weekdays(year, month)
    @_interpolate_weekdays_cache ||= {}
    @_interpolate_weekdays_cache["#{year}-#{month}"] ||= interpolate_weekdays_without_cache(year, month)
  end

  def interpolate_weekdays_without_cache(year, month)
    t = Date.new(year, month, 1)
    valid_mday, _, mday_field = time_specs[:dom]
    valid_wday, _, wday_field = time_specs[:dow]

    # Careful, if both DOW and DOM fields are non-wildcard,
    # then we only need to match *one* for cron to run the job:
    if not (mday_field == '*' and wday_field == '*')
      valid_mday = [] if mday_field == '*'
      valid_wday = [] if wday_field == '*'
    end
    # Careful: crontabs may use either 0 or 7 for Sunday:
    valid_wday << 0 if valid_wday.include?(7)

    result = []
    while t.month == month
      result << t.mday if valid_mday.include?(t.mday) || valid_wday.include?(t.wday)
      t = t.succ
    end

    [Set.new(result), result]
  end

  def nudge_year(t, dir = :next)
    spec = time_specs[:year][1]
    next_value = find_best_next(t.year, spec, dir)
    t.year = next_value || (dir == :next ? spec.first : spec.last)

    # We've exhausted all years in the range
    raise "No matching dates exist" if next_value.nil?
  end

  def nudge_month(t, dir = :next)
    spec = time_specs[:month][1]
    next_value = find_best_next(t.month, spec, dir)
    t.month = next_value || (dir == :next ? spec.first : spec.last)

    nudge_year(t, dir) if next_value.nil?

    # we changed the month, so its likely that the date is incorrect now
    valid_days = interpolate_weekdays(t.year, t.month)[1]
    t.day = dir == :next ? valid_days.first : valid_days.last
  end

  def date_valid?(t, dir = :next)
    interpolate_weekdays(t.year, t.month)[0].include?(t.day)
  end

  def nudge_date(t, dir = :next, can_nudge_month = true)
    spec = interpolate_weekdays(t.year, t.month)[1]
    next_value = find_best_next(t.day, spec, dir)
    t.day = next_value || (dir == :next ? spec.first : spec.last)

    nudge_month(t, dir) if next_value.nil? && can_nudge_month
  end

  def nudge_hour(t, dir = :next)
    spec = time_specs[:hour][1]
    next_value = find_best_next(t.hour, spec, dir)
    t.hour = next_value || (dir == :next ? spec.first : spec.last)

    nudge_date(t, dir) if next_value.nil?
  end

  def nudge_minute(t, dir = :next)
    spec = time_specs[:minute][1]
    next_value = find_best_next(t.min, spec, dir)
    t.min = next_value || (dir == :next ? spec.first : spec.last)

    nudge_hour(t, dir) if next_value.nil?
  end

  def nudge_second(t, dir = :next)
    spec = time_specs[:second][1]
    next_value = find_best_next(t.sec, spec, dir)
    t.sec = next_value || (dir == :next ? spec.first : spec.last)

    nudge_minute(t, dir) if next_value.nil?
  end

  def time_specs
    @time_specs ||= begin
      tokens = substitute_parse_symbols(@source).split(/\s+/)
      # tokens now contains the 5 or 7 fields

      if tokens.count == 5
        {
          :second => parse_element("0", 0..59),       #second
          :minute => parse_element(tokens[0], 0..59), #minute
          :hour   => parse_element(tokens[1], 0..23), #hour
          :dom    => parse_element(tokens[2], 1..31), #DOM
          :month  => parse_element(tokens[3], 1..12), #mon
          :dow    => parse_element(tokens[4], 0..6),  #DOW
          :year   => parse_element("*", 2000..2050)   #year
        }
      elsif tokens.count == 6
        {
          :second => parse_element(tokens[0], 0..59), #second
          :minute => parse_element(tokens[1], 0..59), #minute
          :hour   => parse_element(tokens[2], 0..23), #hour
          :dom    => parse_element(tokens[3], 1..31), #DOM
          :month  => parse_element(tokens[4], 1..12), #mon
          :dow    => parse_element(tokens[5], 0..6),  #DOW
          :year   => parse_element("*", 2000..2050)   #year
        }
      else
        {
          :second => parse_element(tokens[0], 0..59), #second
          :minute => parse_element(tokens[1], 0..59), #minute
          :hour   => parse_element(tokens[2], 0..23), #hour
          :dom    => parse_element(tokens[3], 1..31), #DOM
          :month  => parse_element(tokens[4], 1..12), #mon
          :dow    => parse_element(tokens[5], 0..6),  #DOW
          :year   => parse_element(tokens[6], 2000..2050)  #year
        }
      end
    end
  end

  def substitute_parse_symbols(str)
    SYMBOLS.inject(str.downcase) do |s, (symbol, replacement)|
      s.gsub(symbol, replacement)
    end
  end


  def stepped_range(rng, step = 1)
    len = rng.last - rng.first

    num = len.div(step)
    result = (0..num).map { |i| rng.first + step * i }

    result.pop if result[-1] == rng.last and rng.exclude_end?
    result
  end


  # returns the smallest element from allowed which is greater than current
  # returns nil if no matching value was found
  def find_best_next(current, allowed, dir)
    if dir == :next
      allowed.sort.find { |val| val > current }
    else
      allowed.sort.reverse.find { |val| val < current }
    end
  end

  def validate_source
    unless @source.respond_to?(:split)
      raise ArgumentError, 'not a valid cronline'
    end
    source_length = @source.split(/\s+/).length
    unless (source_length >= 5 && source_length < 8)
      raise ArgumentError, 'not a valid cronline'
    end
  end
end
