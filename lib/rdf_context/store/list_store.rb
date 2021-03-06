require File.join(File.dirname(__FILE__), 'abstract_store')

module RdfContext
  # List storage, most efficient, but slow storage model. Works well for basic parse and serialize.
  class ListStore < AbstractStore
    def initialize(identifier = nil, configuration = {})
      super
      @triples = []
    end
    
    def inspect
      "ListStore[id=#{identifier}, size=#{@triples.length}]"
    end
    
    # 
    # Adds an extant triple to a graph.
    #
    # _context_ and _quoted_ are ignored
    def add(triple, context, quoted = false)
      @triples << triple unless contains?(triple, context)
    end
    
    # Remove a triple from the graph
    #
    # If the triple does not provide a context attribute, removes the triple
    # from all contexts.
    def remove(triple, context, quoted = false)
      @triples.delete(triple)
    end

    # Check to see if this graph contains the specified triple
    def contains?(triple, context = nil)
      @triples.any? {|t| t == triple}
    end

    # Triples from graph, optionally matching subject, predicate, or object.
    # Delegated from Graph. See Graph#triples for details.
    def triples(triple, context = nil)
      subject = triple.subject
      predicate = triple.predicate
      object = triple.object
      
      if subject || predicate || object
        @triples.select do |t|
          next unless t == triple # Includes matching
          
          if block_given?
            yield t
          end
          t
        end.compact
      elsif block_given?
        @triples.each {|triple| yield triple}
      else
        @triples
      end
    end
  end
end