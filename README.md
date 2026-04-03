# cfobsosc
CF OBS OSC Script

A very simple internal OBS OSC Server that will parse an OSC packet for scene transition purposes.
        This is intended to permit OBS to be commanded by another show control system, typically in a live theatre situation.
        <p>Use Examples</p>
        <p>Scene by index: /obs/scene 3   (where /obs/scene is the command and the scene index is an integer parameter)</p>
        <p>Scene by name: /obs/scene Scene3   (where /obs/scene is the command and the scene name is a string parameter)</p>
        <p>Important: Be sure to update your preferred incoming OSC interface and port numbers to match your situation. 
        An OSC Interface address of 0.0.0.0 should bind to all interfaces, however if your situation requires it you may have to be more specific.</p>
        <p>This script depends on the inclusion of a partner script, "ljsocket.lua" by Elias Hogstvedt, so many thanks! Please place it in the same folder as this script or in your profiles obs-script folder.</p>
        <p>Please note that this script or its limited functionality might not be correct for your situation. If you require greater control or a different setup, 
        we highly recommend OSC-for-OBS by Joe Shea. For our applications, we wanted an auto-start, native and embedded, "non-adjustable" solution that did not involve
        a separate bridge application that could be accidentially closed by yhe user. To that end, we accepted the restrictions that came with a native Lua development with OBS.</p>
