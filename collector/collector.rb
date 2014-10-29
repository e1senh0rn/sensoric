#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'
Bundler.require(:default, :development)

require 'json'
require 'singleton'

conf_file = File.join __dir__, "config.json"
CONFIG    = JSON.parse File.new(conf_file, 'r').read, :symbolize_names => true

# db_config = CONFIG[:database]
# db = InfluxDB::Client.new db_config[:database], db_config

# puts db.get_database_list.inspect


class Metrics
  include Singleton

  attr_accessor :previous
  attr_accessor :current

  def run
    @previous = @current
    @current  = Vmstat.snapshot
  end

  def self.fetch
    instance.current
  end

end

class CpuMeter
  attr_accessor :metrics
  attr_accessor :previous, :current, :diff

  VARIANTS = %i(user system nice idle)

  def initialize(metrics)
    @metrics = metrics
  end

  def cores
    metrics.current.cpus.count
  end

  def update_metrics
    return if metrics.previous.nil?
    @previous = metrics.previous.cpus
    @current  = metrics.current.cpus
    @diff = @previous.zip(@current).map {|prev, curr| calculate_diff prev, curr}
  end

  def percentage
    update_metrics

    @previous.zip(@current).map.with_index do |(prev, curr), i|
      cpu = diff[i]
      total = cpu.values.inject(0, &:+)

      VARIANTS.inject({}) do |memo, name|
        memo[name] = Float(cpu[name]) / Float(total) * 100.0 rescue 0.0
        memo
      end
    end
  end


  def calculate_diff(prev, curr)
    VARIANTS.inject({}) do |memo, name|
      value = prev.nil? ? 0 : (curr[name] - prev[name]).abs
      memo[name] = value
      memo
    end
  end

end

Metrics.instance.run

metrics_thread = Thread.new do
  loop do
    Metrics.instance.run
    sleep 1
  end
end

cpu = CpuMeter.new(Metrics.instance)

loop do
  (0..cpu.cores).each do |core|
    total = 100.0 - cpu.percentage[core][:idle]
    puts "Core ##{core}: #{total} %"
  end
  puts "-" * 10
  sleep 1
end
