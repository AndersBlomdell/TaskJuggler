#
# PropertySet.rb - The TaskJuggler III Project Management Software
#
# Copyright (c) 2006, 2007, 2008 by Chris Schlaeger <cs@kde.org>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#


require 'AttributeDefinition'
require 'PropertyTreeNode'

# A PropertySet is a collection of properties of the same kind. Properties can
# be Task, Resources, Scenario, Shift or Accounts objects. All properties of
# the same kind belong to the same PropertySet. A property may only belong to
# one PropertySet in the Project. The PropertySet holds the definitions for
# the attributes. All Properties of the set will have a set of these
# attributes.
class PropertySet

  attr_reader :project, :flatNamespace, :attributeDefinitions

  def initialize(project, flatNamespace)
    if $DEBUG && project.nil?
      raise "project parameter may not be NIL"
    end
    # Indicates whether the namespace of this PropertySet is flat or not. In a
    # flat namespace all property IDs must be unique. Otherwise only the IDs
    # within a group of siblings must be unique. The full ID of the Property
    # is then composed of the siblings ID prefixed by the parent ID. ID fields
    # are separated by dots.
    @flatNamespace = flatNamespace
    # The main Project data structure reference.
    @project = project
    # This is the blueprint for PropertyTreeNode attribute sets. Whever a new
    # PropertTreeNode is created, an attribute is created for each definition
    # in this list.
    @attributeDefinitions = Hash.new
    # A list of all PropertyTreeNodes in this set.
    @properties = Array.new
    # A hash of all PropertyTreeNodes in this set, hashed by their ID. This is
    # the same data as in @properties, but hashed by ID for faster access.
    @propertyMap = Hash.new

    # IDs and names of the built-in attributes. TODO: Check performance impact
    # when making them normal attributes.
    @@fixedAttributeNames = {
      "id" => "ID",
      "name" => "Name",
      "seqno" => "Seq. No."
    }
    # And their types.
    @@fixedAttributesTypes = {
      "id" => :String,
      "name" => :String,
      "seqno" => :Fixnum
    }
  end

  # Inherit all attributes of each property from the parent scenario.
  def inheritAttributesFromScenario
    @properties.each { |p| p.inheritAttributesFromScenario }
  end

  # Call this function to delete all registered properties.
  def clearProperties
    @properties.clear
    @propertyMap.clear
  end

  # Return the index of the top-level _property_ in the set.
  def levelSeqNo(property)
    seqNo = 1
    @properties.each do |p|
      unless p.parent
        return seqNo if p == property
        seqNo += 1
      end
    end
    raise "Fatal Error: Unknow property #{property}"
  end

  # Use the function to declare the various attributes that properties of this
  # PropertySet can have. The attributes must be declared before the first
  # property is added to the set.
  def addAttributeType(attributeType)
    if !@properties.empty?
      raise "Fatal Error: Attribute types must be defined before " +
            "properties are added."
    end

    @attributeDefinitions[attributeType.id] = attributeType
  end

  # Iterate over all attribute definitions.
  def eachAttributeDefinition
    @attributeDefinitions.each do |key, value|
      yield(value)
    end
  end

  # Return true if there is an AttributeDefinition for _attrId_.
  def knownAttribute?(attrId)
    @@fixedAttributeNames.include?(attrId) ||
    @attributeDefinitions.include?(attrId)
  end

  # Return whether the attribute with _attrId_ is scenario specific or not.
  def scenarioSpecific?(attrId)
    # All hardwired attributes are not scenario specific.
    return false if @attributeDefinitions[attrId].nil?

    @attributeDefinitions[attrId].scenarioSpecific
  end

  # Return whether the attribute with _attrId_ is scenario specific or not.
  def inheritable?(attrId)
    # All hardwired attributes are not inheritable.
    return false if @attributeDefinitions[attrId].nil?

    @attributeDefinitions[attrId].inheritable
  end

  # Return whether or not the attribute was user defined.
  def userDefined?(attrId)
    return false if @attributeDefinitions[attrId].nil?

    @attributeDefinitions[attrId].userDefined
  end

  # Return the default value of the attribute.
  def defaultValue(attrId)
    return nil if @attributeDefinitions[attrId].nil?

    @attributeDefinitions[attrId].default
  end

  # Returns the name (human readable description) of the attribute with the
  # Id specified by _attrId_.
  def attributeName(attrId)
    # Some attributes are hardwired into the properties. These need to be
    # treated separately.
    if @@fixedAttributeNames[attrId].nil?
      if @attributeDefinitions.include?(attrId)
        return @attributeDefinitions[attrId].name
      end
    else
      return @@fixedAttributeNames[attrId]
    end

    nil
  end

  # Return the type of the attribute with the Id specified by _attrId_.
  def attributeType(attrId)
    # Hardwired attributes need special treatment.
    if @@fixedAttributesTypes[attrId].nil?
      if @attributeDefinitions.has_key?(attrId)
        @attributeDefinitions[attrId].objClass
      else
        nil
      end
    else
      @@fixedAttributesTypes[attrId]
    end
  end

  # Add the new PropertyTreeNode object _property_ to the set. The set is
  # indexed by ID. In case an object with the same ID already exists in the
  # set it will be overwritten.
  def addProperty(property)
    # The PropertySet defines the set of attribute that each PropertyTreeNode
    # in this set has. Create these attributes with their default values.
    @attributeDefinitions.each do |id, attributeType|
      property.declareAttribute(attributeType)
    end

    # The PropertyTreeNode objects are indexed by ID or hierachical ID
    # depending on the name space setting of this set.
    if @flatNamespace
      @propertyMap[property.id] = property
    else
      @propertyMap[property.fullId] = property
    end
    @properties << property
  end

  # Return the PropertyTreeNode object with ID _id_ from the set or nil if not
  # present.
  def [](id)
    @propertyMap[id]
  end

  # Update the WBS and tree indicies.
  def index
    each do |p|
      wbsIdcs = p.getWBSIndicies
      tree = ""
      wbs = ""
      first = true
      wbsIdcs.each do |idx|
        # Prefix the level index with zeros so that we always have a 5 digit
        # long String. 5 digits should be large enough for all real-world
        # projects.
        tree += idx.to_s.rjust(5, '0')
        if first
          first = false
        else
          wbs += '.'
        end
        wbs += idx.to_s
      end
      p.set('wbs', wbs)
      p.set('tree', tree)
    end
  end

  # Return the maximum used number of breakdown levels. A flat list has a
  # maxDepth of 1. A list with one sub level has a maxDepth of 2 and so on.
  def maxDepth
    md = 0
    each do |p|
      md = p.level if p.level > md
    end
    md + 1
  end

  # Return the number of PropertyTreeNode objects in this set.
  def items
    @properties.length
  end

  # Return the number of top-level PropertyTreeNode objects. Top-Level items
  # are no children.
  def topLevelItems
    items = 0
    @properties.each do |p|
      items += 1 unless p.parent
    end
    items
  end

  # Iterator over all PropertyTreeNode objects in this set.
  def each
    @properties.each do |value|
      yield(value)
    end
  end

  # Return the set of PropertyTreeNode objects as flat Array.
  def to_ary
    @properties
  end

  def to_s
    PropertyList.new(self).to_s
  end

end

