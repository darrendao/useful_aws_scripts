require 'rubygems'
require 'aws-sdk'
require 'date'
require 'pp'

client = AWS::Support::Client.new(
    :access_key_id => 'KEY',
    :secret_access_key => 'SECRET')

check_result = client.describe_trusted_advisor_check_result({:check_id => 'Qch7DwouX1', :language => 'en'})[:result]
flagged_resources =  check_result[:flagged_resources]

puts "EC2 instances that are under 10% utilized:"
flagged_resources.each do |res|
  data = res[:metadata]
  puts "#{data[0]} | #{data[1]} | #{data[2]} | #{data[3]} | #{data[4]} | #{data[19]} | #{data[20]}"
end
