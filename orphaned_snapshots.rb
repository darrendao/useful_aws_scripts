require 'aws-sdk'

region = ARGV[0]
account_id = ARGV[1]

client = Aws::EC2::Client.new(region: region)
ec2 = Aws::EC2::Resource.new(client: client)
iam = Aws::IAM::Resource.new(region: region)

# Try to get account id ourselves if not specified in CLI arg
# I can't believe AWS doesn't provide an easy way to do this
if account_id.nil? 
  if iam.users.first.arn =~ /iam::(\d{12})/
    account_id = $1 
  else
    puts "Unable to determine account id"
    return
  end
end

# Get list of all of the images that I own
my_images = {}
ec2.images(owners: [account_id]).each do |ami|
  my_images[ami.id] = true
end

# Get list of all existing EBS volume ids
vols = {}
ec2.volumes.each do |volume|
  vols[volume.id] = true
end

# Loop through list of snapshots that I own and find the ones
# that don't match up with any existing images
ec2.snapshots(owner_ids: [account_id]).each do |snap|
  if snap.description =~ /Created by CreateImage\(i-(\w{8})\) for ami-(\w{8}) from vol-(\w{8})/
    ami_snapped = "ami-#{$2}"
    if !my_images[ami_snapped]
      puts "#{snap.id} - orphan because #{ami_snapped} no longer exists"
    end
  elsif !vols[snap.volume_id]
      puts "#{snap.id} - orphan because #{snap.volume_id} no longer exists"
  end
end
