#--
# Copyright (c) 2014 SoftLayer Technologies, Inc. All rights reserved.
#
# For licensing information see the LICENSE.md file in the project root.
#++



module SoftLayer
# An +APIParameterFilter+ is an intermediary object that understands how
# to accept the other API parameter filters and carry their values to
# method_missing in Service. Instances of this class are created
# internally by the Service in its handling of a method call and you
# should not have to create instances of this class directly.
#
# Instead, to use an API filter, you add a filter method to the call
# chain when you call a method through a Service
#
# For example, given a Service instance called +account_service+
# you could take advantage of the API filter that identifies a particular
# object known to that service using the object_with_id method :
#
#     account_service.object_with_id(91234).getSomeAttribute
#
# The invocation of object_with_id will cause an instance of this
# class to be created with the service as its target.
#
class APIParameterFilter
  # The target of this API Parameter Filter. Should the filter
  # receive an unknown method call, method_missing will forward
  # the call on to the target. This is supposed to be an instance of
  # the SoftLayer::Service class.
  attr_reader :target

  # The collected parameters represented by this filter.  These parameters
  # are passed along to the target when method_missing is forwarding
  # a message.
  attr_reader :parameters

  # Construct a filter with the given target (and starting parameters if given)
  def initialize(target, starting_parameters = nil)
    @target = target
    @parameters = starting_parameters || {}
  end

  ##
  # API Parameter filters will call through to a particular service
  # but that service is defined by their target
  def service_name
    return @target.service_name
  end

  ##
  # Adds an API filter that narrows the scope of a call to an object with
  # a particular ID. For example, if you want to get the ticket
  # with an ID of 12345 from the ticket service you might use
  #
  #     ticket_service.object_with_id(12345).getObject
  #
  def object_with_id(value)
    # we create a new object in case the user wants to store off the
    # filter chain and reuse it later
    APIParameterFilter.new(self.target, @parameters.merge({ :server_object_id => value }))
  end

  ##
  # Use this as part of a method call chain to add an object mask to
  # the request. The arguments to object mask should be well formed
  # Extended Object Mask strings:
  #
  #   ticket_service.object_mask(
  #     "mask[createDate, modifyDate]",
  #     "mask(SoftLayer_Some_Type).aProperty").getObject
  #
  # The object_mask becomes part of the request sent to the server
  # The object mask strings are parsed into ObjectMaskProperty trees
  # and those trees are stored with the parameters. The trees are
  # converted to strings immediately before the mask is used in a call
  #
  def object_mask(*args)
    raise ArgumentError, "object_mask expects object mask strings" if args.empty? || (1 == args.count && !args[0])
    raise ArgumentError, "object_mask expects strings" if args.find{ |arg| !arg.kind_of?(String) }

    mask_parser = ObjectMaskParser.new()
    object_masks = args.collect { |mask_string| mask_parser.parse(mask_string)}.flatten
    object_mask = (@parameters[:object_mask] || []) + object_masks

    # we create a new object in case the user wants to store off the
    # filter chain and reuse it later
    APIParameterFilter.new(self.target, @parameters.merge({ :object_mask => object_mask }));
  end

  ##
  # Adds a result limit which helps you page through a long list of entities
  #
  # The offset is the index of the first item you wish to have returned
  # The limit describes how many items you wish the call to return.
  #
  # For example, if you wanted to get five open tickets from the account
  # starting with the tenth item in the open tickets list you might call
  #
  #     account_service.result_limit(10, 5).getOpenTickets
  #
  def result_limit(offset, limit)
    # we create a new object in case the user wants to store off the
    # filter chain and reuse it later
    APIParameterFilter.new(self.target, @parameters.merge({ :result_offset => offset, :result_limit => limit }))
  end

  ##
  # Adds an object_filter to the result. An Object Filter allows you
  # to specify criteria which are used to filter the results returned
  # by the server.
  def object_filter(filter)
    raise ArgumentError, "object_filter expects an instance of SoftLayer::ObjectFilter" if filter.nil? || !filter.kind_of?(SoftLayer::ObjectFilter)

    # we create a new object in case the user wants to store off the
    # filter chain and reuse it later
    APIParameterFilter.new(self.target, @parameters.merge({:object_filter => filter}));
  end

  ##
  # A utility method that returns the server object ID (if any) stored
  # in this parameter set.
  def server_object_id
    self.parameters[:server_object_id]
  end

  ##
  # A utility method that returns the object mask (if any) stored
  # in this parameter set.
  def server_object_mask
    if parameters[:object_mask] && !parameters[:object_mask].empty?

      # Reduce the masks found in this object to a minimal set
      #
      # If you pass the API a mask that asks for the same property twice (within
      # the same type scope), the API treats it as an error (and throws an exception)
      #
      # We get around that by parsing the various masks that have been given to us
      # merging their properties where possible, thereby removing the duplicates
      # from the mask that actually gets passed to the server. As a side benefit,
      # the mask we send to the server will be streamlined; without too many extraneous
      # characters
      reduced_masks = parameters[:object_mask].inject([]) do |merged_masks, object_mask|
        mergeable_mask = merged_masks.find { |mask| mask.can_merge_with? object_mask }
        if mergeable_mask
          mergeable_mask.merge object_mask
        else
          merged_masks.push object_mask
        end

        merged_masks
      end

      if reduced_masks.count == 1
        reduced_masks[0].to_s
      else
        "[#{reduced_masks.collect{|mask| mask.to_s}.join(',')}]"
      end
    else
      nil
    end
  end

  ##
  # A utility method that returns the starting index of the result limit (if any) stored
  # in this parameter set.
  def server_result_limit
    self.parameters[:result_limit]
  end

  ##
  # A utility method that returns the starting index of the result limit offset (if any) stored
  # in this parameter set.
  def server_result_offset
    self.parameters[:result_offset]
  end

  ##
  # A utility method that returns the object filter (if any) stored with this filter.
  def server_object_filter
    self.parameters[:object_filter].to_h if self.parameters.has_key?(:object_filter)
  end

  ##
  # This allows the filters to be used at the end of a long chain of calls that ends
  # at a service.  It forwards the message and the parameters to the target of this
  # method (presumably a Service instance)
  def method_missing(method_name, *args, &block)
    puts "SoftLayer::APIParameterFilter#method_missing called #{method_name}, #{args.inspect}" if $DEBUG

    if(!block && method_name.to_s.match(/[[:alnum:]]+/))
      @target.call_softlayer_api_with_params(method_name, self, args)
    else
      super
    end
  end
end

end # module SoftLayer