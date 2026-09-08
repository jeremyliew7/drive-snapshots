const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const source=fs.readFileSync(require('node:path').join(__dirname,'../viewer/app.js'),'utf8');
// Load pure import/model functions before DOM event wiring, with an inert data element.
const context=vm.createContext({document:{getElementById:()=>({textContent:'[]'})}});
vm.runInContext(source.split("$('files').onchange=")[0],context);
const parse=text=>context.parseCSV(text);
test('BOM, CRLF, Unicode, commas, escaped quotes and multiline paths',()=>{
  const rows=parse('\uFEFFDepth,Path,SizeBytes,FileCount\r\n0,"/中文, ""quoted""\nfolder",12,2\r\n');
  assert.equal(rows[0].Path,'/中文, "quoted"\nfolder');assert.equal(rows[0].SizeBytes,12);
});
test('reject missing columns, malformed quotes, invalid sizes and duplicate paths',()=>{
  for(const text of ['Path\n/a','Depth,Path,SizeBytes,FileCount\n0,"/a,1,1','Depth,Path,SizeBytes,FileCount\n0,/a,-1,1','Depth,Path,SizeBytes,FileCount\n0,/a,1,1\n1,/a,2,1'])assert.throws(()=>parse(text));
});
test('legacy rows gain coverage defaults and Windows path normalization',()=>{
  const s=context.prepare({rows:parse('Depth,Path,SizeBytes,FileCount\n0,C:\\,20,2\n1,C:\\Stuff,20,2')});
  assert.equal(s.root.Incomplete,0);assert.equal(s.children.get('c:')[0].SizeBytes,20);
});
test('exported numeric strings normalize and root is required',()=>{
  const s=context.prepare({rows:[{Depth:'0',Path:'/demo',SizeBytes:'40',FileCount:'2'}]});assert.equal(s.root.SizeBytes,40);
  assert.throws(()=>context.prepare({rows:[]}));
});
