%tensor createcmdmaker
runn={'N54643', 'N54645', 'N54647','N54649', 'N54693', 'N54694', 'N54695','N54696','N54697','N54698','N54701','N54702','N54702', 'N54703'};
i=8; 
%for i=9:13
%for i=1:numel(runn)

     runno=runn{i}
     
% %      %j=0;
% %      cmd1=['cp -r /piperspace/' char(runno) '/' char(runno) '_m00'  ' /piperspace/' char(runno) '_m00'];
% %          [status,cmdout] = system(cmd1,'-echo')
% %          
      for j=0:9
% %          
% %          %cmd1=['ln -s /piperspace/' char(runno) '/' char(runno) '_m0' num2str(j) ' /piperspace/' char(runno) '_m0' num2str(j)];
% %          cmd1=['cp -r /piperspace/' char(runno) '/' char(runno) '_m0' num2str(j) ' /piperspace/' char(runno) '_m0' num2str(j)];
% %          [status,cmdout] = system(cmd1,'-echo')
        system(['rm -r /Volumes/piperspace/' runno '_m0' num2str(j) '/' runno '_m0' num2str(j)]);
        %system(['rm /Volumes/piperspace/' runno '_m0' num2str(j) '/' runno '_m0' num2str(j) 'images/*roimx*']);
      end
% %      
     for j=10:33
% %           cmd1=['cp -r /piperspace/' char(runno) '/' char(runno) '_m' num2str(j) ' /piperspace/' char(runno) '_m' num2str(j)];
% %          %cmd1=['ln -s /piperspace/' char(runno) '/' char(runno) '_m' num2str(j) ' /piperspace/' char(runno) '_m' num2str(j)];
% %          [status,cmdout] = system(cmd1,'-echo')
     system(['rm -r /Volumes/piperspace/' runno '_m' num2str(j) '/' runno '_m' num2str(j)]);
     % system(['rm /Volumes/piperspace/' runno '_m' num2str(j) '/' runno '_m' num2str(j) 'images/*roimx*']);
      end
% %   
%most i-s
     cmd1=['roll_3d -x 0 -y 172 -z 0 ' runno '_m00  ' runno '_m01  ' runno '_m02  ' runno '_m03  ' runno '_m04  ' runno '_m05  ' runno '_m06  ' runno '_m07  ' runno '_m08  ' runno '_m09  ' runno '_m10  ' runno '_m11  ' runno '_m12  ' runno '_m13  ' runno '_m14  ' runno '_m15  ' runno '_m16  ' runno '_m17  ' runno '_m18  ' runno '_m19  ' runno '_m20  ' runno '_m21  ' runno '_m22  ' runno '_m23  ' runno '_m24  ' runno '_m25  ' runno '_m26  ' runno '_m27  ' runno '_m28  ' runno '_m29  ' runno '_m30  ' runno '_m31  ' runno '_m32  ' runno '_m33'];
    
    %i=4
    %cmd1=['roll_3d -x 0 -y 12 -z 0 ' runno '_m00  ' runno '_m01  ' runno '_m02  ' runno '_m03  ' runno '_m04  ' runno '_m05  ' runno '_m06  ' runno '_m07  ' runno '_m08  ' runno '_m09  ' runno '_m10  ' runno '_m11  ' runno '_m12  ' runno '_m13  ' runno '_m14  ' runno '_m15  ' runno '_m16  ' runno '_m17  ' runno '_m18  ' runno '_m19  ' runno '_m20  ' runno '_m21  ' runno '_m22  ' runno '_m23  ' runno '_m24  ' runno '_m25  ' runno '_m26  ' runno '_m27  ' runno '_m28  ' runno '_m29  ' runno '_m30  ' runno '_m31  ' runno '_m32  ' runno '_m33'];
    
     [status,cmdout] = system(cmd1,'-echo')
     
     %system(['rm -r /Volumes/piperspace/' runno '_m00/' runno '_m00']);
     cmd2=['/Volumes/workstation_home/software/bin/tensor_create abb -f -n 16.bennett.03 16.bennett.03 9T 34 ' runno '_m00  ' runno '_m01  ' runno '_m02  ' runno '_m03  ' runno '_m04  ' runno '_m05  ' runno '_m06  ' runno '_m07  ' runno '_m08  ' runno '_m09  ' runno '_m10  ' runno '_m11  ' runno '_m12  ' runno '_m13  ' runno '_m14  ' runno '_m15  ' runno '_m16  ' runno '_m17  ' runno '_m18  ' runno '_m19  ' runno '_m20  ' runno '_m21  ' runno '_m22  ' runno '_m23  ' runno '_m24  ' runno '_m25  ' runno '_m26  ' runno '_m27  ' runno '_m28  ' runno '_m29  ' runno '_m30  ' runno '_m31  ' runno '_m32  ' runno '_m33'];
     [status,cmdout] = system(cmd2,'-echo')
     
%      cmd3=['/Volumes/workstation_home/software/bin/archiveme abb ' runno '_m00  ' runno '_m01  ' runno '_m02  ' runno '_m03  ' runno '_m04  ' runno '_m05  ' runno '_m06  ' runno '_m07  ' runno '_m08  ' runno '_m09  ' runno '_m10  ' runno '_m11  ' runno '_m12  ' runno '_m13  ' runno '_m14  ' runno '_m15  ' runno '_m16  ' runno '_m17  ' runno '_m18  ' runno '_m19  ' runno '_m20  ' runno '_m21  ' runno '_m22  ' runno '_m23  ' runno '_m24  ' runno '_m25  ' runno '_m26  ' runno '_m27  ' runno '_m28  ' runno '_m29  ' runno '_m30  ' runno '_m31  ' runno '_m32  ' runno '_m33'];
%      [status,cmdout] = system(cmd3,'-echo')
%      
     %system('tensor_create abb -f -n 16.bennett.03 16.bennett.03 9T 34 N54443_m00 N54443_m01 N54443_m02 N54443_m03 N54443_m04 N54443_m05 N54443_m06 N54443_m07 N54443_m08 N54443_m09 N54443_m10 N54443_m11 N54443_m12 N54443_m13 N54443_m14 N54443_m15 N54443_m16 N54443_m17 N54443_m18 N54443_m19 N54443_m20 N54443_m21 N54443_m22 N54443_m23 N54443_m24 N54443_m25 N54443_m26 N54443_m27 N54443_m28 N54443_m29 N54443_m30 N54443_m31 N54443_m32 N54443_m33');
%system(cmd)

%end