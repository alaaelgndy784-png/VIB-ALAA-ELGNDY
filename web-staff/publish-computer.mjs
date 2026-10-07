import {GoogleAuth} from 'google-auth-library';
import {execFileSync} from 'node:child_process';
import {resolve} from 'node:path';

const project='vib-sales';
const auth=new GoogleAuth({scopes:['https://www.googleapis.com/auth/cloud-platform']});
const client=await auth.getClient();
const billing=await client.request({url:`https://cloudbilling.googleapis.com/v1/projects/${project}/billingInfo`});
if (billing.data.billingEnabled !== false) {
  throw new Error('Publishing stopped: project must have billing disabled (Spark). No plan was changed.');
}
const cli=resolve('web-staff/node_modules/.bin/firebase');
execFileSync(cli,['deploy','--only','hosting','--project',project,'--non-interactive'],{stdio:'inherit'});
console.log('Manager: https://vib-sales.web.app/manager/');
console.log('Staff: https://vib-sales.web.app/staff/');
