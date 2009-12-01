module Reddy
  # List storage, most efficient, but slow storage model. Works well for basic parse and serialize.
  class ListStore < AbstractStore
    # Created with graph that the store is attached to
    def initialize(graph)
      @graph = graph
      @triples = []
    end
    
   ## 
    # Adds an extant triple to a graph.
    # See Graph#store for details.
    #
    # @author Tom Morris
    def << (triple)
      @triples << triple unless contains?(triple)
    end
    
    # Remove a triple from the graph
    #
    # If the triple does not provide a context attribute, removes the triple
    # from all contexts.
    def remove(triple)
      @triples.delete(triple)
    end

    # Check to see if this graph contains the specified triple
    def contains?(triple)
      !@triples.find_index(triple).nil?
    end

    # Triples from graph, optionally matching subject, predicate, or object.
    # Delegated from Graph. See Graph#triples for details.
    #
    # @author Gregg Kellogg
    def triples(options = {})
      subject = options[:subject]
      predicate = options[:predicate]
      object = options[:object]
      if subject || predicate || object
        @triples.select do |triple|
          next if subject && triple.subject != subject
          next if predicate && triple.predicate != predicate
          case object
          when Regexp
            next unless object.match(triple.object.to_s)
          when URIRef, BNode, Literal, String
            next unless triple.object == object
          end
            
          yield triple if block_given?
          triple
        end.compact
      elsif block_given?
        @triples.each {|triple| yield triple}
      else
        @triples
      end
    end
  end
end