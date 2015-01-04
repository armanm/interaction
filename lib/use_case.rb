require "active_model"
require "wisper"

require "use_case/version"
require "use_case/module_customiser"
require "use_case/validation_helpers"
require "use_case/params"

module UseCase
  # Override Ruby's module inclusion hook to prepend base with our #perform
  # method, extend base with a .perform method, include Params for Virtus and
  # ActiveSupport::Validation, and include Wisper for pub/sub.
  #
  # @api private
  def self.included(base)
    base.class_eval do
      prepend Perform
      extend ClassMethods
      include InstanceMethods
      include Params
      include ActiveModel::Validations
      include Wisper::Publisher
    end
  end

  # Includes a customised use case module.
  #
  # @param options [Hash]
  # @option options [TrueClass,FalseClass] :validations
  #
  # @example
  #   include UseCase.use_case(validations: false)
  #
  # @return [Module]
  # @since 0.0.1
  def self.use_case(options = {})
    validations = options.fetch(:validations, true)
    ModuleCustomiser.new do
      prepend Perform
      extend ClassMethods
      include InstanceMethods
      include Params
      if validations
        include ActiveModel::Validations
      end
      include Wisper::Publisher
    end
  end

  # Includes a customised params module.
  #
  # @param options [Hash]
  # @option options [TrueClass,FalseClass] :validations
  #
  # @example
  #   include UseCase.params(validations: false)
  #
  # @return [Module]
  # @since 0.0.1
  def self.params(options = {})
    validations = options.fetch(:validations, true)
    ModuleCustomiser.new do
      include Params
      if validations
        include ActiveModel::Validations
      end
    end
  end

  include ValidationHelpers

  module Perform
    # Executes use case logic
    #
    # Use cases must implement this method. Assumes success if failure is not
    # called.
    #
    # @since 0.0.1
    # @api public
    def perform
      catch :halt do
        super.tap do
          success unless result_specified?
        end
      end
    end
  end

  module ClassMethods
    # Executes and returns the use case
    #
    # A use case object is instantiated with the supplied
    # arguments, perform is called and the object is returned.
    #
    # @param args [*args] Arguments to initialize the use case with
    #
    # @return [Object] returns the use case object
    #
    # @since 0.0.1
    # @api public
    def perform(*args)
      new(*args).tap do |use_case|
        use_case.perform
      end
    end
  end

  module InstanceMethods
    # Indicates if the use case was successful
    #
    # @return [TrueClass, FalseClass]
    #
    # @since 0.0.1
    # @api public
    def success?
      !failed?
    end

    # Indicates whether the use case failed
    #
    # @return [TrueClass, FalseClass]
    #
    # @since 0.0.1
    # @api public
    def failed?
      !!@failed
    end

    # Attach a success callback using wisper
    #
    # @see Wisper
    #
    # @example
    #   use_case = SignUp.new(params)
    #   use_case.on_success do
    #     # handle success
    #   end
    #   use_case.perform
    #
    # @since 0.0.1
    # @api public
    def on_success(&block)
      on(namespaced_name(:success), &block)
    end

    # Attach a failure callback
    #
    # @see Wisper
    #
    # @example
    #   use_case = SignUp.new(params)
    #   use_case.on_failure do
    #     # handle failure
    #   end
    #   use_case.perform
    #
    # @since 0.0.1
    # @api public
    def on_failure(&block)
      on(namespaced_name(:failure), &block)
    end

    private

    # Mark the use case as successful and publish the event with
    # Wisper.
    #
    # @return [TrueClass]
    #
    # @since 0.0.1
    # @api public
    def success(args = nil)
      @failed = false
      publish(namespaced_name(:success), args)
      true
    end

    # Mark the use case as failed and publish the event with
    # Wisper.
    #
    # @return [FalseClass]
    #
    # @since 0.0.1
    # @api public
    def failure(args = nil)
      @failed = true
      publish(namespaced_name(:failure), args)
      throw :halt
    end

    # Return an event name namespaced by the underscored class name
    #
    # @return [String]
    #
    # @example
    #   namespaced_event(:success)
    #   # => "sign_up_success"
    #   namespaced_event(:failure)
    #   # => "sign_up_failure"
    #
    # @since 0.0.1
    # @api private
    def namespaced_name(event)
      [self.class.model_name.param_key, event].join('_')
    end

    # Halts execution of the use case if validation fails and
    # published errors with Wisper.
    #
    # @since 0.0.1
    # @api public
    def validate!
      failure(errors) unless valid?
    end

    # Indicates whether the use case called success or failure
    #
    # @return [TrueClass, FalseClass]
    #
    # @api private
    # @since 0.0.1
    def result_specified?
      defined?(@failed)
    end
  end
end
