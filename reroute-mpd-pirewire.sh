#!/bin/bash

CMDS=$(mktemp -u)
EVENTS=$(mktemp -u)
mkfifo "$CMDS"
mkfifo "$EVENTS"
cat "$EVENTS" > /dev/null &

pw-cli < "$CMDS" > "$EVENTS" &

listMpdNodes() {
    echo "$(pw-dump | jq '.[] | select((.info.props."node.name" | tostring | test(".*mpd.*")) and .type == "PipeWire:Interface:Node") | .id')"
}

mpdNodes=""
while true; do

newMpdNodes="$(listMpdNodes)"

if [ "$mpdNodes" == "$newMpdNodes" ]; then
    sleep 5;
    continue;
else
    echo "Nodes changed updating"
    mpdNodes="$newMpdNodes"
fi

output1NodeId=$(pw-dump | jq '.[] | select(.info.props."node.name" == "mpd.Output1" and .type == "PipeWire:Interface:Node") | .id')
output2NodeId=$(pw-dump | jq '.[] | select(.info.props."node.name" == "mpd.Output2" and .type == "PipeWire:Interface:Node") | .id')

sinkNodeId=$(pw-dump | jq '.[] | select(.info.props."alsa.card" == 0 and .info."n-input-ports" == 2) | .id' )

sinkPort1=$(pw-dump | jq ".[] | select(.type == \"PipeWire:Interface:Port\" and .info.props.\"node.id\" == $sinkNodeId and .info.props.\"audio.channel\" == \"FL\" and .info.props.\"port.direction\" == \"in\") | .id")
sinkPort2=$(pw-dump | jq ".[] | select(.type == \"PipeWire:Interface:Port\" and .info.props.\"node.id\" == $sinkNodeId and .info.props.\"audio.channel\" == \"FR\" and .info.props.\"port.direction\" == \"in\") | .id")

# Delete all links for nodes
for nodeId in $output1NodeId $output2NodeId; do
    for id in $(pw-dump | jq ".[] | select(.info.props.\"link.output.node\" == $nodeId) | .id" ); do
        pw-cli destroy $id
    done
done

links=""
if [ -n "$output1NodeId" ]; then
    ports=$(pw-dump | jq ".[] | select(.type == \"PipeWire:Interface:Port\" and .info.props.\"node.id\" == $output1NodeId and .info.props.\"port.direction\" == \"out\") | .id")
    echo "set-param $output1NodeId \"Props { channelVolumes: [0.2, 0.2] }\"" > "$CMDS"
    for port in $ports; do
        echo "create-link $output1NodeId $port $sinkNodeId $sinkPort1" > "$CMDS"
    done
fi
if [ -n "$output2NodeId" ]; then
    ports=$(pw-dump | jq ".[] | select(.type == \"PipeWire:Interface:Port\" and .info.props.\"node.id\" == $output2NodeId and .info.props.\"port.direction\" == \"out\") | .id")
    echo "set-param $output2NodeId \"Props { channelVolumes: [0.2, 0.2] }\"" > "$CMDS"
    for port in $ports; do
        echo "create-link $output2NodeId $port $sinkNodeId $sinkPort2" > "$CMDS"
    done
fi
done
