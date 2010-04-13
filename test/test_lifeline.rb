require 'helper'

class TestBlockExecutionException < StandardError
end

class TestLifeline < Test::Unit::TestCase
  include Lifeline
  
  context "get_process_list" do
    should "return an array of process hashes" do
      processes = get_process_list
      assert_kind_of(Array, processes)
      processes.all? do |p|
        assert_kind_of(Hash, p)
        assert_not_nil p[:pid]
        assert_kind_of(Integer, p[:pid])
        assert_not_nil p[:command]
        assert_kind_of(String, p[:command])
      end
    end
  end
  
  context "lifeline" do
    should "raise an ArgumentError when not passed a block" do
      assert_raise(ArgumentError) { lifeline }
    end
    
    context "when the process list is empty" do
      setup do
        self.expects(:get_process_list).returns(nil)
      end
      
      should "raise a RuntimeError and exit without executing the block" do
        assert_raise(RuntimeError) do 
          lifeline do
            flunk "This block should not be executed"
          end
        end
      end
    end
    
    context "when the process list does not contain the PID for this process" do
      setup do
        self.expects(:get_process_list).returns([{:pid => $$+1, :command => "random commmand"}])
      end
      
      should "raise a RuntimeError and exit" do
        assert_raise(RuntimeError) do
          lifeline do
            flunk "This block should not be executed"
          end
        end
      end
    end
    
    context "when there is no other process with the same command (different pid) as this one" do
      should "execute the provided block" do
        assert_raise(TestBlockExecutionException) do
          lifeline do
            raise TestBlockExecutionException, "This block throws an exception to show the block was run"
          end
        end
      end
    end
    
    context "when there is another process with the same command (different pid)" do
      setup do
        @processes = get_process_list
        my_process = @processes.detect {|p| p[:pid] == $$}
        assert_not_nil my_process
        @processes << {:pid => $$ + 10, :command => my_process[:command]}
        self.expects(:get_process_list).returns(@processes)
      end
      
      should "not execute the provided block" do
        lifeline do
          flunk "This block should not be executed"
        end
      end
    end
  end

  context "define_lifeline_tasks" do
    setup do
      define_lifeline_tasks("awesome:namespace") do
        raise TestBlockExecutionException, "This block throws an exception to show the block was run"
      end
    end
    
    should "create an awesome:namespace:run task" do
      assert_raise(TestBlockExecutionException) do
        Rake::Task["awesome:namespace:run"].invoke
      end
    end
    
    should "create an awesome:namespace:lifeline task" do
      assert_not_nil Rake::Task["awesome:namespace:lifeline"]
    end
    
    should "create an awesome:namespace:terminate task" do
      assert_not_nil Rake::Task["awesome:namespace:terminate"]
    end
  end
end