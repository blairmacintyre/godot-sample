#!/usr/bin/env python3
"""Bundle a self-contained offline browser preview with local Three.js sources."""
import base64,json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
text=(root/'source/preview_template.html').read_text()
for token,file in [('THREE','three.module.js'),('UTIL','BufferGeometryUtils.js'),('LOADER','GLTFLoader.js'),('ORBIT','OrbitControls.js')]:
    script=(root/'viewer/vendor'/file).read_text().replace("'../utils/BufferGeometryUtils.js'","'buffer-utils'")
    text=text.replace('__'+token+'_URL__','data:text/javascript;base64,'+base64.b64encode(script.encode()).decode())
text=text.replace('__MODEL_B64__',base64.b64encode((root/'office.glb').read_bytes()).decode())
stats=json.loads((root/'asset_info.json').read_text())['statistics']
text=text.replace('17,238 triangles',f"{stats['triangles']:,} triangles")
(root/'preview.html').write_text(text)
print('Bundled preview.html:',len(text),'bytes')
