#!/usr/bin/env ruby
#
# Author: Darren Dao
#
# This script downloads billing reports from AWS (csv files), parses them and  pulls out line 
# items belonging to a list of specified linked accounts. Such functionality is useful for
# giving linked account owners their own billing reports without revealing billing info
# of other linked accounts.
#
# Usage example #1: Download latest billing report from "mybilling" S3 bucket, and pull out 
# billing info for accounts 123 and 456. Results are stored under "myresults" directory.
#
#   ruby get_linked_account_billing.rb -d myresults -l 123,456 -b mybilling
#
# Usage example #2: Same as last command but download reports from the month October of 2013
#   
#   ruby get_linked_account_billing.rb -d myresults -l 123,456 -b mybilling --ym 2013-10
#
# Usage example #3: Download and generate cost allocation report instead.
#
#   ruby get_linked_account_billing.rb -d myresults -l 123,456 -b mybilling --no-cleanup --ym 2013-10 -t aws-cost-allocation
#
# Output files have the following naming convention: linkedaccountid-masteraccountid-billingreporttype-year-month.csv

require 'rubygems'
require 'aws-sdk'
require 'optparse'
require 'ostruct'
require 'fileutils'

$masteraccount_id = '1234567890'
AWS.config(
    :access_key_id => 'ABCHANGEMEBA',
    :secret_access_key => 'abcdedarrendaofghij')

class String
  def rchomp(sep = $/)
    self.start_with?(sep) ? self[sep.size..-1] : self
  end
end

def parse_file(billing_file, opts)
  puts "parsing #{billing_file}"
  outdir = opts.outdir
  basename = File.basename(billing_file)

  filemap = {}
  opts.linked_accounts.each do |account|
    filename = File.join(outdir, "#{account}-#{basename}")
    filemap[account] = File.open(filename, 'w')
  end

  first_line = true
  File.open(billing_file).each do |line|
    # first line is the column definitions
    if first_line
      first_line = false
      filemap.each do |account, file|
        file.write(line)
      end
      next
    end

    # Only print out rows with the third column (linked account column) that matches
    # the specified account id
    tokens = line.split(",")
    current_account = tokens[2].rchomp('"').chomp('"')
    if opts.linked_accounts.include?(current_account)
      filemap[current_account].write(line)
    end
  end

  # close files
  filemap.each do |account, file|
    file.close
  end
end

def fetch_file(opts)
   s3 = AWS::S3.new
   if opts.report_type =~ /detailed/
     key = "#{$masteraccount_id}-#{opts.report_type}-#{opts.ym}.csv.zip"
   else
     key = "#{$masteraccount_id}-#{opts.report_type}-#{opts.ym}.csv"
   end
   obj = s3.buckets[opts.bucket].objects[key]
   unless obj.exists?
     puts "Unable to find billing report for #{opts.ym}"
     exit 1
   end

   # Download
   FileUtils.mkdir_p(opts.outdir)
   outfile = File.join(opts.outdir, key)
   puts "Downloading to #{outfile}"
   File.open(outfile, 'wb') do |file|
     obj.read do |chunk|
       file.write(chunk)
     end
   end
   return outfile
end

def unzip(file, options)
  outdir = options.outdir
  cmd = "unzip -o #{file} -d #{outdir}"
  puts cmd
  `#{cmd}`
  return File.join(outdir, File.basename(file, ".zip"))
end

options = OpenStruct.new
options.ym = Time.now.strftime("%Y-%m")
options.outdir = 'results'
options.cleanup = true
options.report_type = 'aws-billing-detailed-line-items-with-resources-and-tags'

opts = OptionParser.new(nil, 24, '  ')
opts.banner = "Usage: #{__FILE__} [options]"
opts.on('--cred', '-c', '=FILE', 'File containing AWS credentials') do |opt|
  options.cred = opt 
end
opts.on('--bucket', '-b', '=BUCKET', "S3 bucket where billing reports are stored") do |opt|
  options.bucket = opt 
end
opts.on('--ym', '=year-month', 'Year and month (yyyy-mm) to pull the billing info from') do |opt|
  options.ym = opt 
end
opts.on('--outdir', '-d', '=OUTPUT_DIR', 'Where to save the outputs') do |opt|
  options.outdir = opt
end
opts.on('--type', '-t', '=REPORTTYPE', 'Type of report (defaults to aws-billing-detailed-line-items-with-resources-and-tags)') do |opt|
  options.report_type = opt
end
opts.on('--[no-]cleanup', 'Whether to clean up downloaded files') do |opt|
  options.cleanup = opt
end
opts.on('--linkedaccounts account1,account2,account3', '-l', Array, 'Accounts to pull out billing info for') do |opt|
  options.linked_accounts = opt 
end
opts.on_tail("-h", "--help", "Show this message") do
  puts opts
  exit 
end

leftovers = opts.parse(ARGV)

if ARGV.length == 0
  puts opts
  exit 0
end

if options.linked_accounts.nil? or options.linked_accounts.empty?
  puts "You need to specify linked accounts"
  puts opts
  exit 0
end

outfile = fetch_file(options)
outfile = unzip(outfile, options) if options.report_type =~ /detailed/
parse_file(outfile, options)

# clean up
if options.cleanup
  FileUtils.rm_f(outfile)
  FileUtils.rm_f("#{outfile}.zip")
end
