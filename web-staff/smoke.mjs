import {webkit,chromium} from 'playwright';
import {createServer} from 'node:http';
import {readFile, mkdir} from 'node:fs/promises';
import {resolve,extname} from 'node:path';
const root=resolve('web-project/build/web');
const types={'.html':'text/html','.js':'application/javascript','.json':'application/json','.wasm':'application/wasm','.png':'image/png'};
const server=createServer(async(req,res)=>{
  try {const path=resolve(root,'.'+decodeURIComponent(new URL(req.url,'http://localhost').pathname));
    if(!path.startsWith(root+'/') && path!==root){res.writeHead(403).end();return;}
    const file=path===root?root+'/index.html':path;
    res.setHeader('Content-Type',types[extname(file)]??'application/octet-stream');res.end(await readFile(file));
  }catch{res.writeHead(404).end();}
});
await new Promise(r=>server.listen(8085,'127.0.0.1',r));
await mkdir('web-project/smoke',{recursive:true});
try{
  for(const [name,engine] of [['iphone-webkit',webkit],['mobile-chromium',chromium]]){
    const browser=await engine.launch();
    try{
      const page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:2,isMobile:true,hasTouch:true});
      const errors=[];page.on('pageerror',e=>errors.push(e.message));
      await page.goto('http://127.0.0.1:8085');
      await page.locator('flt-semantics-placeholder').click({force:true,timeout:120000});
      await page.getByText('دخول',{exact:true}).waitFor({timeout:60000});
      await page.screenshot({path:`web-project/smoke/${name}.png`});
      if(errors.length) throw new Error(`${name}: ${errors.join('; ')}`);
      console.log(`${name}: login rendered, no uncaught JavaScript errors`);
    }finally{await browser.close();}
  }
}finally{server.close();}
