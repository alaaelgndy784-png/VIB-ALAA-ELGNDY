import {GoogleAuth} from 'google-auth-library';
import {execFileSync} from 'node:child_process';
import {resolve} from 'node:path';
const project='vib-sales';
const auth=new GoogleAuth({scopes:['https://www.googleapis.com/auth/cloud-platform']});
const client=await auth.getClient();
// Fail closed: no billing changes, no deployment on a paid plan.
const billing=await client.request({url:`https://cloudbilling.googleapis.com/v1/projects/${project}/billingInfo`});
if (billing.data.billingEnabled !== false) throw new Error('Publishing stopped: project must have billing disabled (Spark). No plan was changed.');
const cli=resolve('web-staff/node_modules/.bin/firebase');
const webAppId='1:200962643703:web:f11fbe2ff566c7352c65f2';
execFileSync('flutter',['build','web','--release','--no-wasm-dry-run',`--dart-define=FIREBASE_WEB_APP_ID=${webAppId}`],{cwd:'web-project',stdio:'inherit'});
execFileSync(cli,['deploy','--only','hosting','--project',project,'--non-interactive'],{cwd:'web-project',stdio:'inherit'});
console.log('Free employee URL: https://vib-sales.web.app');
