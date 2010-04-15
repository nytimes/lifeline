require 'rake'
require 'rake/tasklib'

module Lifeline
  ##
  # @private
  def get_process_list
    processes = %x{ps ax -o pid,command}

    return nil if processes.nil?

    processes.split(/\n/).map do |p|
      if p =~ /^\s*(\d+)\s(.+)$/
        {:pid => $1.to_i, :command => $2.strip}
      end
    end.compact
  end

  ##
  # A method for executing a block of code only if there is no other process with the same command running. This is useful if you want
  # to have a perpetually running daemon that only executes once at a time. It uses the process name returned by ps ax to see if there is
  # a process with the same command name but a different PID already executing. If so, it terminates without running the block. NOTE: since it
  # uses the command name returned from <tt>ps ax</tt>, it us up to to you to name the process containing this code with a distinctly unique name. If two
  # separate Rails projects both have a <tt>rake lifeline</tt> task they WILL interfere with each other. I'd suggest prefixing with the project name (ie, 
  # <tt>doc_viewer:lifeline</tt>) to be sure
  #
  # @param &block a block which is executed if there is not already a lifeline running.
  # @raise [ArgumentError] if you do not pass in a block argument
  def lifeline
    if !block_given?
      raise ArgumentError, "You must pass in a block to be the body of the run rake task"
    end

    my_pid = $$
    processes = get_process_list

    if processes.nil? || processes.empty?
      raise "No processes being returned by get_process_list. Aborting!"
    end

    myself = processes.detect {|p| p[:pid] == my_pid}
    if myself.nil?
      raise "Unable to find self (PID=#{my_pid}) in process list. This is bizarre to say the least. Exiting.\n#{processes.map {|p| p.inspect}.join("\n")}"
    end

    # there isn't already another process running with the same command
    if !processes.any? {|p| p[:pid] != my_pid && p[:command] == myself[:command]}
      yield
    end
  end

  # Define rake tasks for running, starting, and terminating
  class LifelineRakeTask < ::Rake::TaskLib
    # The namespace to define the tasks in
    # @return [String] the namespace for the tasks
    attr_accessor :namespace

    ##
    # Creates 3 new tasks for the lifeline in the namespace specified. These
    # tasks are
    # * run - a task for running the code provided in the block
    # * lifeline - a lifeline task for running the run task if it's not already running
    # * terminate - a task for terminating all lifelines.
    # 
    # @param [String, Symbol] name the namespace of the rake tasks
    # @param [optional, Hash] opts Additional options for the method
    # @option opts [Array<String, Symbol>] :prereqs ([]) If there any any rake tasks that should be prerequisites of the :run task, specify them here (For Rails, you would do :prereqs => :environment)
    # @param a block that defines the body of the run task
    def initialize(namespace, opts={}, &block)
      if !block_given?
        raise ArgumentError, "You must pass in a block to be the body of the run rake task"
      end

      @namespace = namespace

      define_run_task(opts, &block)
      define_lifeline_task
      define_terminate_task
    end

    protected

    def run_task_name
      "#{namespace}:run"
    end

    def define_run_task(opts={}, &block)
      desc "Runs the #{namespace}:run task"
      
      task_arg = if opts[:prereqs]
        {run_task_name => opts[:prereqs]}
      else
        run_task_name
      end
      
      task(task_arg, &block)
    end

    def define_lifeline_task
      desc "A lifeline task for executing only one process of #{namespace}:run at a time"
      task("#{namespace}:lifeline") do
        lifeline do
          Rake::Task["#{namespace}:run"].invoke
        end
      end
    end

    def define_terminate_task
      desc "Terminates any running #{namespace}:lifeline tasks"
      task("#{namespace}:terminate") do
        unless (process = %x{ps aux | grep "#{namespace}:lifeline" | grep ruby | grep -v grep}.chomp).empty?
          runner_pid = process.gsub(/(\s+)/, ' ').split(' ')[1]
          puts %x{kill -9 #{runner_pid}}
        end
      end
    end
  end

  ##
  # A method that defines 3 rake tasks for doing lifelines:
  # * <tt>namespace:run</tt> runs the specified block
  # * <tt>namespace:lifeline</tt> a lifeline for executing only a single copy of <tt>namespace:run</tt> at a time
  # * <tt>namespace:terminate</tt> a task for terminating the lifelines
  #
  # @param [String,Symbol] namespace the namespace to define the 3 tasks in
  # @param &block a block which defines the body of the namespace:run method
  #
  # @raise [ArgumentError] if you do not pass in a block argument
  def define_lifeline_tasks(namespace, &block)
    LifelineRakeTask.new(namespace, &block)
  end
end
