require_relative './helper'
require_relative '../lib/tq'

def setup_test_logger!
  TestUtils.setup_logger( File.basename(__FILE__,'.rb') )
end

class QueueSpecTests < Minitest::Spec

  describe "QueueSpec.from_hash" do
    
    it "QueueSpec.from_hash with string keys should work" do

      q = TQ::QueueSpec.from_hash( {
        'project' =>  'PROJECT',
        'location' =>  'us-central1',
        'name' =>  'QUEUE',
        'lease_duration' =>  '200s',
        'max_tasks' =>  1
      })

      assert_equal '200s', q.lease_duration
      assert_equal 1, q.max_tasks

    end

  end

end


