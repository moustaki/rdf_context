require File.join(File.dirname(__FILE__), 'abstract_serializer')

module RdfContext
  # Serialize RDF graphs in NTriples format
  class XmlSerializer < RecursiveSerializer
    VALID_ATTRIBUTES = [:none, :untyped, :typed]
    
    def initialize(graph)
      super
      @force_RDF_about = {}
    end
    
    # Serialize the graph
    #
    # @param [IO, StreamIO] stream:: Stream in which to place serialized graph
    # @param [Hash] options:: Options for parser
    # <em>options[:base]</em>:: Base URI of graph, used to shorting URI references
    # <em>options[:max_depth]</em>:: Maximum depth for recursively defining resources, defaults to 3
    # <em>options[:lang]</em>:: Output as root xml:lang attribute, and avoid generation xml:lang where possible
    # <em>options[:attributes]</em>:: How to use XML attributes when serializing, one of :none, :untyped, :typed. The default is none.
    #
    # -- Serialization Examples
    # attributes == :none
    #
    #   serialize(io, :attributes => none)
    def serialize(stream, options = {})
      @max_depth = options[:max_depth] || 3
      @base = options[:base]
      @lang = options[:lang]
      @attributes = options[:attributes] || :none
      raise "Invalid attribute option '#{@attributes}', should be one of #{VALID_ATTRIBUTES.to_sentence}" unless VALID_ATTRIBUTES.include?(@attributes.to_sym)
      
      doc = Nokogiri::XML::Document.new

      preprocess

      predicates = @graph.predicates.uniq
      possible = predicates | @graph.objects.uniq
      namespaces = {}
      required_namespaces = {}
      possible.each do |res|
        next unless res.is_a?(URIRef)
        if !get_qname(res)  # Creates Namespace mappings
          [RDF_NS, DC_NS, OWL_NS, LOG_NS, RDF_NS, RDFS_NS, XHV_NS, XML_NS, XSD_NS, XSI_NS].each do |ns|
            # Bind a standard namespace to the graph and try the lookup again
            @graph.bind(ns) if ns.uri == res.base
            required_namespaces[res.base] = true if !get_qname(res) && predicates.include?(res)
          end
        end
      end
      add_namespace(RDF_NS)
      add_namespace(XML_NS) if @base || @lang
      
      # See if there's a default namespace, and favor it when generating element names.
      # Lookup an equivalent prefixed namespace for use in generating attributes
      @default_ns = @graph.namespace("")
      if @default_ns
        add_namespace(@default_ns)
        prefix = @graph.prefix(@default_ns.uri)
        @prefixed_default_ns = @graph.namespace(prefix)
        add_namespace(@prefixed_default_ns) if @prefixed_default_ns
      end
      
      # Add bindings for predicates not already having bindings
      tmp_ns = "ns0"
      required_namespaces.keys.each do |uri|
        puts "serialize: create temporary namespace for <#{uri}>" if $DEBUG
        add_namespace(Namespace.new(uri, tmp_ns))
        tmp_ns = tmp_ns.succ
      end

      doc.root = Nokogiri::XML::Element.new("rdf:RDF", doc)
      @namespaces.each_pair do |p, ns|
        if p.to_s.empty?
          doc.root.default_namespace = ns.uri.to_s
        else
          doc.root.add_namespace(p, ns.uri.to_s)
        end
      end
      doc.root["xml:lang"] = @lang if @lang
      doc.root["xml:base"] = @base if @base
      
      # Add statements for each subject
      order_subjects.each do |subject|
        #puts "subj: #{subject.inspect}"
        subject(subject, doc.root)
      end

      doc.write_xml_to(stream, :encoding => "UTF-8", :indent => 2)
    end
    
    protected
    def subject(subject, parent_node)
      node = nil
      
      if !is_done?(subject)
        subject_done(subject)
        properties = @graph.properties(subject)
        prop_list = sort_properties(properties)
        puts "subject: #{subject.to_n3}, props: #{properties.inspect}" if $DEBUG

        rdf_type, *rest = properties.fetch(RDF_TYPE.to_s, [])
        properties[RDF_TYPE.to_s] = rest
        if rdf_type.is_a?(URIRef)
          element = get_qname(rdf_type)
          if rdf_type.namespace && @default_ns && rdf_type.namespace.uri == @default_ns.uri
            element = rdf_type.short_name
          end
        end
        element ||= "rdf:Description"

        node = Nokogiri::XML::Element.new(element, parent_node.document)
      
        if subject.is_a?(BNode)
          # Only need nodeID if it's referenced elsewhere
          node["rdf:nodeID"] = subject.to_s if ref_count(subject) > (@depth == 0 ? 0 : 1)
        else
          node["rdf:about"] = relativize(subject)
        end

        prop_list.each do |prop|
          prop_ref = URIRef.new(prop)
          
          properties[prop].each do |object|
            @depth += 1
            predicate(prop_ref, object, node, properties[prop].length == 1)
            @depth -= 1
          end
        end
      elsif @force_RDF_about.include?(subject)
        puts "subject: #{subject.to_n3}, force about" if $DEBUG
        node = Nokogiri::XML::Element.new("rdf:Description", parent_node.document)
        node["rdf:about"] = relativize(subject)
        @force_RDF_about.delete(subject)
      end

      parent_node.add_child(node) if node
    end
    
    # Output a predicate into the specified node.
    #
    # If _is_unique_ is true, this predicate may be able to be serialized as an attribute
    def predicate(prop, object, node, is_unique)
      qname = prop.to_qname(uri_binding)

      # See if we can serialize as attribute.
      # * untyped attributes that aren't duplicated where xml:lang == @lang
      # * typed attributes that aren't duplicated if @dt_as_attr is true
      # * rdf:type
      as_attr = false
      as_attr ||= true if [:untyped, :typed].include?(@attributes) && prop == RDF_TYPE

      # Untyped attribute with no lang, or whos lang is the same as the default and RDF_TYPE
      as_attr ||= true if [:untyped, :typed].include?(@attributes) &&
        (object.is_a?(Literal) && object.untyped? && (object.lang.nil? || object.lang == @lang))
      
      as_attr ||= true if [:typed].include?(@attributes) && object.is_a?(Literal) && object.typed?

      as_attr = false unless is_unique
      
      # Can't do as an attr if the qname has no prefix and there is no prefixed version
      if @default_ns && prop.namespace.uri == @default_ns.uri
        if as_attr
          if @prefixed_default_ns
            qname = "#{@prefixed_default_ns.prefix}:#{prop.short_name}"
          else
            as_attr = false
          end
        else
          qname = prop.short_name
        end
      end

      puts "predicate: #{qname}, as_attr: #{as_attr}, object: #{object.inspect}, done: #{is_done?(object)}, sub: #{@subjects.include?(object)}" if $DEBUG
      qname = "rdf:li" if qname.match(/rdf:_\d+/)
      pred_node = Nokogiri::XML::Element.new(qname, node.document)
      
      if object.is_a?(Literal) || is_done?(object) || !@subjects.include?(object)
        # Literals or references to objects that aren't subjects, or that have already been serialized
        
        args = object.xml_args
        puts "predicate: args=#{args.inspect}" if $DEBUG
        attrs = args.pop
        
        if as_attr
          # Serialize as attribute
          pred_node.unlink
          pred_node = nil
          node[qname] = object.is_a?(URIRef) ? relativize(object) : object.to_s
        else
          # Serialize as element
          attrs.each_pair do |a, av|
            next if a == "xml:lang" && av == @lang # Lang already specified, don't repeat
            av = relativize(object) if a == "#{RDF_NS.prefix}:resource"
            puts "  elt attr #{a}=#{av}" if $DEBUG
            pred_node[a] = av.to_s
          end
          puts "  elt #{'xmllit ' if object.is_a?(Literal) && object.xmlliteral?}content=#{args.first}" if $DEBUG && !args.empty?
          if object.is_a?(Literal) && object.xmlliteral?
            pred_node.add_child(Nokogiri::XML::CharacterData.new(args.first, node.document))
          elsif args.first
            pred_node.content = args.first unless args.empty?
          end
        end
      else
        # Check to see if it can be serialized as a collection
        col = @graph.seq(object)
        conformant_list = col.all? {|item| !item.is_a?(Literal)}
        o_props = @graph.properties(object)
        if conformant_list && o_props[RDF_NS.first.to_s]
          # Serialize list as parseType="Collection"
          pred_node["rdf:parseType"] = "Collection"
          col.each do |item|
            # Mark the BNode subject of each item as being complete, so that it is not serialized
            @graph.triples(Triple.new(nil, RDF_NS.first, item)) do |triple, ctx|
              subject_done(triple.subject)
            end
            @force_RDF_about[item] = true
            subject(item, pred_node)
          end
        else
          if @depth < @max_depth
            @depth += 1
            subject(object, pred_node)
            @depth -= 1
          elsif object.is_a?(BNode)
            pred_node["rdf:nodeID"] = object.identifier
          else
            pred_node["rdf:resource"] = relativize(object)
          end
        end
      end
      node.add_child(pred_node) if pred_node
    end
  end
end