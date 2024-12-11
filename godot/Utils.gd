extends Node

func findNodeDescendantsInGroup(node: Node, groupName: String) -> Array:
	var descendantsInGroup := []
	for child in node.get_children():
		if child.is_in_group(groupName):
			descendantsInGroup.append(child)
		descendantsInGroup += findNodeDescendantsInGroup(child, groupName)
	return descendantsInGroup
