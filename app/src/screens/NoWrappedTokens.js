import React from "react";
import { Button, EmptyStateCard, GU, LoadingRing } from "@aragon/ui";
import emptyStateImg from "../assets/empty-state.svg";
import { useAragonApi } from "@aragon/api-react";
import styled from "styled-components";
import { useAppLogic } from "../app-logic";

const NoWrappedTokens = React.memo(function NoWrappedTokens({ isSyncing }) {
  const { api, appState } = useAragonApi();
  const {
    orgTokenAddress,
    wrappedTokenAddress,
    orgTokenBalance,
    wrappedTokenBalance
  } = appState;
  const { actions } = useAppLogic();

  return (
    <Box>
      <EmptyStateCard
        text={
          isSyncing ? (
            <div
              css={`
                display: grid;
                align-items: center;
                justify-content: center;
                grid-template-columns: auto auto;
                grid-gap: ${1 * GU}px;
              `}
            >
              <LoadingRing />
              <span>Syncing…</span>
            </div>
          ) : (
            "No tokens here!"
          )
        }
        action={
          <Button wide mode="strong" onClick={actions.wrapTokens}>
            Wrap token
          </Button>
        }
        illustration={
          <img
            css={`
              margin: auto;
              height: 170px;
            `}
            src={emptyStateImg}
            alt="No tokens here"
          />
        }
      />
    </Box>
  );
});

const Box = styled.div`
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100vh;
`;

export default NoWrappedTokens;
