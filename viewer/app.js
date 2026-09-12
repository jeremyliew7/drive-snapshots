'use strict';
const $ = id => document.getElementById(id);
let snapshots = JSON.parse($('snapshot-data').textContent), selected = '', timer, page=0, hovered='', rectangles=[];
const pageSize=300;
const fmt = n => {const sign=n<0?'−':'';n=Math.abs(n);let i=0;while(n>=1024&&i<4){n/=1024;i++;}return sign+n.toLocaleString('en',{maximumFractionDigits:1})+' '+['B','KiB','MiB','GiB','TiB'][i];};
const name = p => p.replace(/[\\/]$/,'').split(/[\\/]/).pop() || p;
const key = p => /^[a-z]:|^\\\\/i.test(p) ? p.toLowerCase().replace(/\\/g,'/').replace(/\/$/,'') : p.replace(/\/$/,'');
const parent = p => key(p).replace(/\/[^/]*$/,'');
function parseCSV(text) {
  const rows=[];let row=[],field='',quoted=false;
  text=text.replace(/^\uFEFF/,'');
  for(let i=0;i<text.length;i++){const c=text[i];if(c==='"'){if(quoted&&text[i+1]==='"'){field+='"';i++;}else quoted=!quoted;}else if(c===','&&!quoted){row.push(field);field='';}else if((c==='\n'||c==='\r')&&!quoted){if(c==='\r'&&text[i+1]==='\n')i++;row.push(field);if(row.some(Boolean))rows.push(row);row=[];field='';}else field+=c;}
  if(quoted)throw Error('Unclosed CSV quote');row.push(field);if(row.some(Boolean))rows.push(row);
  const headers=rows.shift()||[];for(const h of ['Path','Depth','SizeBytes','FileCount'])if(!headers.includes(h))throw Error('Missing column: '+h);
  const seen=new Set();return rows.map(r=>{if(r.length!==headers.length)throw Error('Invalid CSV column count');const o=Object.fromEntries(headers.map((h,i)=>[h,r[i]]));for(const h of ['Depth','SizeBytes','FileCount','Unreadable','Reparse','Incomplete']){o[h]=Number(o[h]||0);if(!Number.isSafeInteger(o[h])||o[h]<0)throw Error('Invalid '+h);}if(!o.Path||seen.has(key(o.Path)))throw Error('Empty or duplicate path');seen.add(key(o.Path));return o;});
}
function prepare(s){s.rows=s.rows.map(r=>({...r,Depth:Number(r.Depth),SizeBytes:Number(r.SizeBytes),FileCount:Number(r.FileCount),Unreadable:Number(r.Unreadable||0),Incomplete:Number(r.Incomplete||0),Reparse:Number(r.Reparse||0)}));s.root=s.rows.find(r=>r.Depth===0);if(!s.root||s.rows.filter(r=>r.Depth===0).length!==1)throw Error('Each CSV must contain exactly one depth-0 root');s.depth=s.rows.reduce((n,r)=>Math.max(n,r.Depth),0);s.index=new Map(s.rows.map(r=>[key(r.Path),r]));s.children=new Map();for(const r of s.rows){if(r.Depth===0)continue;const p=parent(r.Path);if(!s.children.has(p))s.children.set(p,[]);s.children.get(p).push(r);}s.full=s.rows.every(r=>r.SnapshotScope==='Full');s.sorted=[...s.rows].sort((a,b)=>key(a.Path).localeCompare(key(b.Path)));return s;}
function option(value,label){const o=document.createElement('option');o.value=value;o.textContent=label;return o;}
function init(){snapshots.forEach(s=>{if(!s.index)prepare(s);});snapshots.sort((a,b)=>a.label.localeCompare(b.label));$('current').replaceChildren(...snapshots.map((s,i)=>option(i,s.label)));$('baseline').replaceChildren(option('','No comparison'),...snapshots.map((s,i)=>option(i,s.label)));$('current').value=String(snapshots.length-1);$('baseline').value=snapshots.length>1?String(snapshots.length-2):'';selected='';page=0;setDepth();render();}
function folderURL(path){
  if(/^[a-z]:[\\/]/i.test(path))return 'file:///'+path.replace(/\\/g,'/').split('/').map((x,i)=>i===0?x:encodeURIComponent(x)).join('/');
  if(path.startsWith('/'))return 'file://'+path.split('/').map(encodeURIComponent).join('/');
  if(path.startsWith('\\\\'))return 'file://'+path.slice(2).replace(/\\/g,'/').split('/').map(encodeURIComponent).join('/');
  return null;
}
function visibleRows(s,root,depth,query){
  const current=s.index.get(root),prefix=root+'/';
  return s.sorted.filter(r=>(key(r.Path)===root||key(r.Path).startsWith(prefix))&&r.Depth-current.Depth<=depth&&r.Path.toLowerCase().includes(query));
}
function frontier(s,root,depth){
  const result=[],start=s.index.get(root),stack=[start];
  while(stack.length){const r=stack.pop(),children=s.children.get(key(r.Path))||[];
    if(!children.length||r.Depth-start.Depth>=depth){if(r.SizeBytes>0)result.push(r);continue;}
    const remainder=Math.max(0,r.SizeBytes-children.reduce((n,c)=>n+c.SizeBytes,0));
    if(remainder)result.push({Path:r.Path,SizeBytes:remainder,detail:true});
    for(const c of children)if(c.SizeBytes>0)stack.push(c);
  }
  return result.sort((a,b)=>b.SizeBytes-a.SizeBytes);
}
function setDepth(){
  const s=snapshots[Number($('current').value)];if(!s)return;
  $('depth').replaceChildren(option('all','All levels'),...Array.from({length:s.depth+1},(_,i)=>option(i,String(i))));
  const preferred=Number(s.root.ViewDepth);
  $('depth').value=Number.isInteger(preferred)&&preferred>=0&&preferred<=s.depth?String(preferred):'all';
}
function navigate(path){selected=key(path);page=0;render();showPath(path);}
function showPath(path,bytes){
  hovered=path;$('hover').textContent=path+(bytes===undefined?'':' · '+fmt(bytes));
  const url=folderURL(path);$('path-link').hidden=!url;
  if(url){$('path-link').href=url;$('path-link').textContent='Open folder ↗';$('path-link').title=url;}
}
function drawMap(items){
  const canvas=$('canvas'),width=$('map').clientWidth,height=$('map').clientHeight;
  const scale=window.devicePixelRatio||1;canvas.width=width*scale;canvas.height=height*scale;
  const ctx=canvas.getContext('2d');ctx.scale(scale,scale);rectangles=[];
  if(!items.length){ctx.fillStyle='#97a4b4';ctx.fillText('No measured bytes in this folder.',16,25);return;}
  const sums=[0];for(const r of items)sums.push(sums[sums.length-1]+r.SizeBytes);
  const stack=[[0,items.length,0,0,width,height]],colors=['#b6efb0','#82c7b3','#94bfe3','#c2b0de','#e7c58e','#91afce'];
  while(stack.length){const [lo,hi,x,y,w,h]=stack.pop();
    if(hi-lo===1){const r=items[lo];ctx.fillStyle=colors[lo%colors.length];ctx.fillRect(x,y,Math.max(0,w-1),Math.max(0,h-1));
      if(w>=1&&h>=1)rectangles.push({x,y,w,h,r});
      // Never force labels into a tile that cannot contain them.
      const label=(r.detail?'Direct files / detail':name(r.Path));ctx.font='600 13px system-ui';
      if(h>=45&&w>=ctx.measureText(label).width+18){ctx.fillStyle='#12201e';ctx.fillText(label,x+8,y+20);ctx.font='12px system-ui';ctx.fillText(fmt(r.SizeBytes),x+8,y+38);}
      continue;
    }
    const total=sums[hi]-sums[lo],half=sums[lo]+total/2;let a=lo+1,b=hi-1;
    while(a<b){const mid=(a+b)>>1;if(sums[mid]<half)a=mid+1;else b=mid;}
    const cut=a,f=(sums[cut]-sums[lo])/total;
    if(w>=h){stack.push([cut,hi,x+w*f,y,w*(1-f),h],[lo,cut,x,y,w*f,h]);}
    else stack.push([cut,hi,x,y+h*f,w,h*(1-f)],[lo,cut,x,y,w,h*f]);
  }
}
function render(){
  if(!snapshots.length)return;
  const s=snapshots[Number($('current').value)], b=$('baseline').value===''?null:snapshots[Number($('baseline').value)];
  const compatible=b&&key(s.root.Path)===key(b.root.Path)&&(s.full&&b.full||s.depth===b.depth&&!s.full&&!b.full);
  const incomplete=s.rows.some(r=>r.Incomplete||r.Unreadable)||(compatible&&b.rows.some(r=>r.Incomplete||r.Unreadable));
  const unknown=s.root.Coverage==='Unknown'||(compatible&&b.root.Coverage==='Unknown');
  $('message').textContent=(s.synthetic?'SYNTHETIC DEMO · ':'')+(b&&!compatible?'Comparison disabled: choose the same root and reported depth.':incomplete?'Partial coverage: sizes are lower bounds; differences may reflect unreadable folders.':unknown?'Coverage unknown: this scanner export does not report unreadable descendants.':'Files stay local. History follows filename order; choose a baseline to explore changes.');
  $('total').textContent=fmt(s.root.SizeBytes);$('count').textContent=s.root.FileCount.toLocaleString();$('delta').textContent=compatible?((s.root.SizeBytes>=b.root.SizeBytes?'+':'')+fmt(s.root.SizeBytes-b.root.SizeBytes)):'—';$('coverage').textContent=incomplete?'Partial':unknown?'Unknown':'No errors flagged';
  if(!selected||!s.index.has(selected))selected=key(s.root.Path);
  const current=s.index.get(selected);showPath(current.Path);$('folder').textContent=current.Path;$('date').textContent=`${Number($('current').value)+1} / ${snapshots.length} snapshots`;
  const relativeDepth=$('depth').value==='all'?Infinity:Number($('depth').value);
  const query=$('search').value.toLowerCase();
  const visible=visibleRows(s,selected,relativeDepth,query);
  page=Math.min(page,Math.max(0,Math.ceil(visible.length/pageSize)-1));
  const fragment=document.createDocumentFragment();
  for(const r of visible.slice(page*pageSize,(page+1)*pageSize)){
    const button=document.createElement('button');
    button.className='tree-row'+(key(r.Path)===selected?' active':'');
    button.style.paddingLeft=(10+Math.min(r.Depth-current.Depth,10)*12)+'px';
    button.textContent=(r.Reparse?'↗ ':'▸ ')+name(r.Path)+' · '+fmt(r.SizeBytes);
    button.title=r.Path;button.onmouseenter=()=>showPath(r.Path,r.SizeBytes);button.onfocus=()=>showPath(r.Path,r.SizeBytes);
    button.onclick=()=>navigate(r.Path);fragment.append(button);
  }
  $('tree').replaceChildren(fragment);
  $('pages').textContent=`${visible.length.toLocaleString()} folders · ${page+1}/${Math.max(1,Math.ceil(visible.length/pageSize))}`;
  $('prev').disabled=page===0;$('next').disabled=(page+1)*pageSize>=visible.length;
  const children=s.children.get(selected)||[];
  drawMap(frontier(s,selected,relativeDepth));
  $('changes').replaceChildren();
  if(compatible){const old=b.children.get(selected)||[];const paths=new Set([...children,...old].map(r=>key(r.Path)));const changes=[...paths].map(p=>{const now=s.index.get(p),before=b.index.get(p);return {path:(now||before).Path,delta:(now?.SizeBytes||0)-(before?.SizeBytes||0),status:!now?'not observed':!before?'newly observed':''};}).filter(r=>r.delta||r.status).sort((a,b)=>Math.abs(b.delta)-Math.abs(a.delta));for(const c of changes.slice(0,50)){const el=document.createElement('div'),left=document.createElement('span'),right=document.createElement('span');el.className='change';left.textContent=name(c.path)+(c.status?' · '+c.status:'');right.className=c.delta>=0?'positive':'negative';right.textContent=(c.delta>=0?'+':'')+fmt(c.delta);el.append(left,right);$('changes').append(el);}if(!changes.length)$('changes').textContent='No changes in immediate child folders.';}else $('changes').textContent='Select a compatible baseline to see folder changes.';
}
$('files').onchange=async e=>{try{const batch=[];for(const f of e.target.files)batch.push(prepare({label:f.name,rows:parseCSV(await f.text())}));snapshots=batch;init();}catch(err){$('message').textContent='Import failed: '+err.message;}};
$('current').onchange=()=>{page=0;setDepth();render();};$('baseline').onchange=render;$('search').oninput=()=>{page=0;render();};$('up').onclick=()=>{const s=snapshots[Number($('current').value)];if(s){selected=parent(selected);page=0;render();}};
$('play').onclick=()=>{if(timer){clearInterval(timer);timer=null;$('play').textContent='▶ Play history';return;}if(snapshots.length<2)return;$('play').textContent='❚❚ Pause';timer=setInterval(()=>{$('current').value=String((Number($('current').value)+1)%snapshots.length);render();},1800);};
$('export').onclick=async()=>{try{if(!snapshots.length)throw Error('Import snapshots first');const doc=document.documentElement.cloneNode(true);doc.querySelector('#snapshot-data').textContent=JSON.stringify(snapshots.map(({label,rows,synthetic})=>({label,rows,synthetic}))).replace(/</g,'\\u003c');const link=doc.querySelector('link[rel="stylesheet"]'),script=doc.querySelector('script[src]');if(link){const style=document.createElement('style');style.textContent=await (await fetch(link.href)).text();link.replaceWith(style);}if(script){const inline=document.createElement('script');inline.textContent=await(await fetch(script.src)).text();script.replaceWith(inline);}const blob=new Blob(['<!doctype html>\n'+doc.outerHTML],{type:'text/html'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='drive-snapshots-report.html';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);}catch(err){$('message').textContent='Export: '+err.message+'. For file:// use export-report.ps1, or open via a local HTTP server.';}};
$('depth').onchange=()=>{page=0;render();};
$('prev').onclick=()=>{page--;render();};$('next').onclick=()=>{page++;render();};
$('canvas').onmousemove=e=>{const bounds=e.currentTarget.getBoundingClientRect(),x=e.clientX-bounds.left,y=e.clientY-bounds.top;const hit=rectangles.find(r=>x>=r.x&&x<r.x+r.w&&y>=r.y&&y<r.y+r.h);if(hit){showPath(hit.r.Path,hit.r.SizeBytes);e.currentTarget.title=hit.r.Path+' — '+fmt(hit.r.SizeBytes);}};
$('canvas').onclick=e=>{const bounds=e.currentTarget.getBoundingClientRect(),x=e.clientX-bounds.left,y=e.clientY-bounds.top;const hit=rectangles.find(r=>x>=r.x&&x<r.x+r.w&&y>=r.y&&y<r.y+r.h);if(hit)navigate(hit.r.Path);};
$('copy-path').onclick=async()=>{try{await navigator.clipboard.writeText(hovered||selected);$('hover').textContent='Path copied.';}catch{ $('hover').textContent='Copy this path: '+(hovered||selected); }};
let resizeTimer;window.addEventListener('resize',()=>{clearTimeout(resizeTimer);resizeTimer=setTimeout(render,100);});
init();
