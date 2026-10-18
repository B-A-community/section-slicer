load File.expand_path('helper.rb', __dir__)
session = BACommunity::SectionSlicer::Session.current
session.close if session
SSTest.clean
puts 'cleaned'
